

/*
 *  Author: Arvin Schnell <arvin@suse.de>
 */


#include <scr/Y2AgentComponent.h>
#include <scr/Y2CCAgentComponent.h>

#include "PamAgent.h"


typedef Y2AgentComp <PamAgent> Y2PamAgentComp;

Y2CCAgentComp <Y2PamAgentComp> g_y2ccag_pam ("ag_pam");

