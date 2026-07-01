import logging
import uvicorn
from fastapi import FastAPI
from config import config
from routers.incident_router import router as incident_router
from routers.health_router import router as health_router

# --- Logging setup (SRP: tập trung tại đây, không rải rác) ---
logging.basicConfig(
    level=getattr(logging, config.LOG_LEVEL, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


# --- App bootstrap ---
app = FastAPI(title=config.APP_NAME)
app.include_router(incident_router)
app.include_router(health_router)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
