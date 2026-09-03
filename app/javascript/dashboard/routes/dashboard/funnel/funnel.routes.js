import { frontendURL } from '../../../helper/URLHelper';
import FunnelIndex from './pages/FunnelIndex.vue';
import FunnelReport from './pages/FunnelReport.vue';

// Sem featureFlag no meta: o modulo e ligado por account.settings.funnel_kanban_enabled, nao
// por feature_flags. A propria pagina cuida do estado desligado, e a API recusa por conta.
//
// custom_role entra na lista porque permissionsHelper devolve 'custom_role' para quem tem um
// papel personalizado, mesmo o account_user sendo agent. Sem ele o roteador barraria um agente
// que a API deixaria passar; quem manda de verdade e Funnel::BoardPolicy.
const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/funnel'),
    component: FunnelIndex,
    name: 'funnel_view',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/funnel/report'),
    component: FunnelReport,
    name: 'funnel_report',
    meta,
  },
];
