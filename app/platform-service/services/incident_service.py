import logging
from models.incident import TriageRequest, TriageResponse
from interfaces.notifier import INotifier
from interfaces.ticket_creator import ITicketCreator
from interfaces.ai_client import IAiClient
from config import config

logger = logging.getLogger(__name__)


class IncidentService:
    def __init__(self, ai_client: IAiClient, ticket_creator: ITicketCreator, notifier: INotifier) -> None:
        self._ai_client = ai_client
        self._ticket_creator = ticket_creator
        self._notifier = notifier

    async def handle(self, request: TriageRequest) -> dict:
        logger.info(f"Processing incident triage for: {request.incident_id}")
        import asyncio
        import uuid

        # 1. Gọi AI Engine
        try:
            response: TriageResponse = await self._ai_client.triage(request)
            ai_failed = False
        except Exception as e:
            logger.error(f"Failed to call AI engine: {e}")
            ai_failed = True
            response = None

        if not ai_failed and response:
            ticket = response.ticket_payload
            ticket_summary = ticket.summary
            ticket_description = ticket.description
        else:
            ticket_summary = f"[Fallback] {request.alert.severity.upper()} alert on {request.alert.service}"
            ticket_description = (
                f"AI Engine was unavailable or returned an error.\n"
                f"Incident ID: {request.incident_id}\n"
                f"Alert: {request.alert.title}\n"
                f"Description: {request.alert.description or 'No description'}\n"
                f"Severity: {request.alert.severity}\n"
                f"Correlation ID: {request.correlation_id}\n"
                f"Tenant ID: {request.tenant_id}"
            )

        # 2. Lấy ticket payload và tạo Jira Ticket
        try:
            ticket_id = await asyncio.to_thread(
                self._ticket_creator.create_ticket,
                summary=ticket_summary,
                description=ticket_description
            )
        except Exception as e:
            logger.error(f"Failed to create Jira ticket: {e}")
            ticket_id = f"{config.JIRA_PROJECT_KEY}-FAIL-{uuid.uuid4().hex[:4].upper()}"

        # 3. Gửi Slack Notifier
        ticket_url = f"{config.JIRA_URL.rstrip('/')}/browse/{ticket_id}" if config.JIRA_URL else None
        ticket_link = f"<{ticket_url}|{ticket_id}>" if ticket_url else ticket_id

        if not ai_failed and response:
            action_text = "\n".join([f"- {a.summary}" for a in response.recommended_actions])
            message = (
                f"🚨 *AI Triage Report: {ticket_link}*\n"
                f"*Status:* {response.status} (Confidence: {response.confidence})\n"
                f"*Root Cause:* {response.suspected_root_cause.summary}\n"
                f"*Recommended Actions:*\n{action_text}"
            )
            if response.suggested_assignee_account_id:
                message += (
                    f"\n*Suggested Assignee (Jira Account ID):* {response.suggested_assignee_account_id}\n"
                    f"*Suggestion Reason:* {response.suggestion_reason or 'N/A'}"
                )
        else:
            message = (
                f"⚠️ *AI Triage Unavailable (Fallback: {ticket_link})*\n"
                f"*Service:* {request.alert.service}\n"
                f"*Severity:* {request.alert.severity}\n"
                f"*Alert:* {request.alert.title}\n"
                f"*Error:* AI Engine failed to respond."
            )

        try:
            await asyncio.to_thread(self._notifier.notify, message)
        except Exception as e:
            logger.error(f"Failed to send Slack notification: {e}")

        return {
            "status": "fallback" if ai_failed else "success",
            "ticket_id": ticket_id,
            "environment": config.ENV_NAME,
        }
