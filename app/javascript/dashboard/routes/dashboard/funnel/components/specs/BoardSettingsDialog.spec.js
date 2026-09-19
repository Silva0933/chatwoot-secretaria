import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import BoardSettingsDialog from '../BoardSettingsDialog.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const agents = [
  { id: 7, name: 'Jailson' },
  { id: 8, name: 'Bruno' },
];

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter =>
    ({
      'agents/getVerifiedAgents': ref(agents),
      'inboxes/getInboxes': ref([]),
    })[getter],
}));

vi.mock('dashboard/stores/funnel', () => ({
  useFunnelStore: () => ({
    getUIFlags: { savingBoardSettings: false },
    updateBoard: vi.fn(),
    replaceBoardMembers: vi.fn(),
    replaceBoardInboxes: vi.fn(),
  }),
}));

/**
 * O combo real guarda `ref(props.modelValue)` — a MESMA instancia do array do pai —, da push
 * nela e emite a propria referencia de volta. Esse stub reproduz exatamente isso, porque e o
 * detalhe que causava a falha: emitir um array novo nao reproduz o bug.
 */
const AliasingComboBoxStub = {
  props: ['modelValue'],
  emits: ['update:modelValue'],
  methods: {
    select(value) {
      this.modelValue.push(value);
      this.$emit('update:modelValue', this.modelValue);
    },
  },
  template: '<div data-test="members-combo" />',
};

const SelectStub = {
  props: ['modelValue', 'options'],
  emits: ['update:modelValue'],
  template: '<select data-test="select" />',
};

const mountDialog = () =>
  mount(BoardSettingsDialog, {
    props: {
      board: {
        id: 1,
        name: 'Venda de Sites',
        description: '',
        currency: 'BRL',
        members: [],
        inboxIds: [],
        automationSettings: {},
      },
    },
    global: {
      stubs: {
        Dialog: { template: '<div><slot /></div>' },
        Button: true,
        Input: true,
        TextArea: true,
        Select: SelectStub,
        TagMultiSelectComboBox: AliasingComboBoxStub,
      },
    },
  });

describe('BoardSettingsDialog', () => {
  // Regressao: escolher um membro derrubava o dialogo inteiro com "Cannot read properties of
  // undefined (reading 'role')". O papel do agente recem-marcado era preenchido por um
  // watch em `memberIds`, que nunca disparava porque a identidade do `.value` nao mudava — e o
  // template chegava em `roles[id].role` antes de `roles[id]` existir.
  it('keeps the dialog alive when a member is picked', async () => {
    const wrapper = mountDialog();

    await wrapper.findComponent(AliasingComboBoxStub).vm.select(7);
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-test="members-combo"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Jailson');
  });

  // O papel e o escopo do membro novo precisam existir para os dois selects da linha: sem eles
  // a linha renderiza sem nada que o operador possa ajustar.
  it('gives the new member a role and a visibility scope', async () => {
    const wrapper = mountDialog();

    await wrapper.findComponent(AliasingComboBoxStub).vm.select(7);
    await wrapper.vm.$nextTick();

    const selects = wrapper.findAllComponents(SelectStub);
    expect(selects.length).toBe(2);
    expect(selects[0].props('modelValue')).toBe('member');
    expect(selects[1].props('modelValue')).toBe('all_tasks');
  });

  // Dois agentes seguidos: o segundo passa pelo mesmo caminho e nao pode derrubar a lista nem
  // apagar o papel que o primeiro ja tinha.
  it('keeps the first member intact when a second one is picked', async () => {
    const wrapper = mountDialog();
    const combo = wrapper.findComponent(AliasingComboBoxStub);

    await combo.vm.select(7);
    await combo.vm.select(8);
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).toContain('Jailson');
    expect(wrapper.text()).toContain('Bruno');
    expect(wrapper.findAllComponents(SelectStub).length).toBe(4);
  });
});
