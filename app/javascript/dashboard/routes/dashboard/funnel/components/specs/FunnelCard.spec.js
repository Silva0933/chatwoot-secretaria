import { mount } from '@vue/test-utils';
import FunnelCard from '../FunnelCard.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt_BR' } }),
}));

vi.mock('dashboard/stores/funnel', () => ({
  useFunnelStore: () => ({ getActiveBoard: { currency: 'BRL' } }),
}));

const ChannelIconStub = {
  props: ['inbox'],
  template: '<i data-test="channel" />',
};

const IconStub = {
  props: ['icon'],
  template: '<i :data-icon="icon" />',
};

// dueState compara DIA DE CALENDARIO, nao diferenca de horas: "daqui a 2h" cai no dia seguinte
// quando o teste roda perto da meia-noite, e o fuso da maquina muda onde esse limite fica. Com o
// relogio parado ao meio-dia e as datas montadas em hora local, o resultado nao depende de quando
// nem de onde a suite roda.
const NOON = new Date(2026, 2, 10, 12, 0, 0);
const at = (day, hour) => new Date(2026, 2, day, hour, 0, 0).toISOString();

const mountCard = task =>
  mount(FunnelCard, {
    props: { task: { id: 1, title: 'Pizzaria Teste', ...task } },
    global: {
      stubs: {
        Avatar: true,
        FunnelCardMenu: true,
        OnClickOutside: { template: '<div><slot /></div>' },
        ChannelIcon: ChannelIconStub,
        Icon: IconStub,
      },
    },
  });

describe('FunnelCard', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOON);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('labels', () => {
    it('shows each label with its colour', () => {
      const wrapper = mountCard({
        labels: [
          { id: 1, title: 'agendado', color: '#ff0000' },
          { id: 2, title: 'em-atendimento', color: '#00ff00' },
        ],
      });

      expect(wrapper.text()).toContain('agendado');
      expect(wrapper.text()).toContain('em-atendimento');
      expect(wrapper.html()).toContain('rgb(255, 0, 0)');
    });

    // Tres cabem na largura da coluna; o resto vira contagem em vez de quebrar o card em
    // quatro linhas de etiqueta.
    it('caps the list at three and counts the rest', () => {
      const wrapper = mountCard({
        labels: [1, 2, 3, 4, 5].map(id => ({
          id,
          title: `etiqueta-${id}`,
          color: '#888888',
        })),
      });

      expect(wrapper.text()).toContain('etiqueta-3');
      expect(wrapper.text()).not.toContain('etiqueta-4');
      expect(wrapper.text()).toContain('+2');
    });

    it('draws no label row when the card has none', () => {
      expect(mountCard({ labels: [] }).text()).not.toContain('+');
    });
  });

  describe('origin', () => {
    it('shows the channel icon and how many conversations are linked', () => {
      const wrapper = mountCard({
        channel: { channelType: 'Channel::Whatsapp', name: 'WhatsApp' },
        conversations: [{ id: 1 }, { id: 2 }],
      });

      expect(wrapper.find('[data-test="channel"]').exists()).toBe(true);
      expect(wrapper.text()).toContain('2');
    });

    it('omits both when the card came from no conversation', () => {
      const wrapper = mountCard({ channel: null, conversations: [] });

      expect(wrapper.find('[data-test="channel"]').exists()).toBe(false);
    });
  });

  // O ponto da mudanca: o prazo volta ao card, mas so nos dois estados que pedem acao. Um card
  // que vence em doze dias nao muda o que alguem faz agora.
  describe('due date', () => {
    it('shows it when overdue', () => {
      const wrapper = mountCard({ dueAt: at(8, 12) });
      expect(wrapper.text()).toContain('FUNNEL.CARD.OVERDUE');
    });

    // Ainda hoje, mas ja passou da hora marcada: continua sendo atraso, nao "hoje".
    it('counts an hour already past today as overdue', () => {
      const wrapper = mountCard({ dueAt: at(10, 9) });
      expect(wrapper.text()).toContain('FUNNEL.CARD.OVERDUE');
    });

    it('shows it when due later today', () => {
      const wrapper = mountCard({ dueAt: at(10, 18) });
      expect(wrapper.text()).toContain('FUNNEL.CARD.TODAY');
    });

    it('stays quiet for tomorrow and beyond', () => {
      const tomorrow = mountCard({ dueAt: at(11, 9) });
      const later = mountCard({ dueAt: at(22, 9) });

      [tomorrow, later].forEach(wrapper => {
        expect(wrapper.text()).not.toContain('FUNNEL.CARD.OVERDUE');
        expect(wrapper.text()).not.toContain('FUNNEL.CARD.TODAY');
      });
    });

    it('stays quiet when there is no deadline', () => {
      const wrapper = mountCard({ dueAt: null });
      expect(wrapper.text()).not.toContain('FUNNEL.CARD.TODAY');
    });
  });

  // A pergunta que o relogio do cliente nao responde. Em "Proposta enviada" e "Reuniao marcada" o
  // agente respondeu por ultimo, o waiting_since e nulo e o relogio some: sem este selo a coluna
  // inteira ficava sem nenhuma nocao de tempo.
  describe('time in stage', () => {
    const hourglass = wrapper =>
      wrapper.find('[data-icon="i-lucide-hourglass"]');

    it('shows how long the card has been sitting in an open stage', () => {
      const wrapper = mountCard({
        stepStageType: 'open',
        stepChangedAt: at(7, 12),
        waitingSince: null,
      });

      expect(hourglass(wrapper).exists()).toBe(true);
      expect(wrapper.text()).toContain('3d');
    });

    // Em Ganho e Perdido o atendimento acabou: ali o numero mede o tempo desde o fechamento,
    // cresce para sempre e nao pede acao nenhuma.
    it('stays quiet once the card is won or lost', () => {
      ['won', 'lost'].forEach(stageType => {
        const wrapper = mountCard({
          stepStageType: stageType,
          stepChangedAt: at(7, 12),
        });

        expect(hourglass(wrapper).exists()).toBe(false);
      });
    });

    it('stays quiet without a stage timestamp', () => {
      const wrapper = mountCard({ stepStageType: 'open', stepChangedAt: null });

      expect(hourglass(wrapper).exists()).toBe(false);
    });

    // Os dois relogios convivem: um diz que o cliente espera, o outro que o card nao anda.
    it('sits alongside the waiting clock without replacing it', () => {
      const wrapper = mountCard({
        stepStageType: 'open',
        stepChangedAt: at(7, 12),
        waitingSince: at(10, 8),
      });

      expect(hourglass(wrapper).exists()).toBe(true);
      expect(wrapper.find('[data-icon="i-lucide-clock"]').exists()).toBe(true);
    });
  });
});
