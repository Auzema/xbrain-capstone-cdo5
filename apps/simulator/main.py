from fastapi import FastAPI, Response
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from routers import jira, slack, health, dumbproxy, ai_engine

app = FastAPI(title="Mock Services for Jira, Slack, AI Engine and Telemetry Simulator")

# Include the routers
app.include_router(health.router)
app.include_router(jira.router)
app.include_router(slack.router)
app.include_router(dumbproxy.router)
app.include_router(ai_engine.router)

@app.get("/metrics")
async def metrics():
    """
    Expose metrics cho Prometheus quét (thay thế cho start_http_server ở code cũ)
    """
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
