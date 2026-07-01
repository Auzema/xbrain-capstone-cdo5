"""CDO MVP worker orchestration package."""

from .worker import WorkerConfig, process_message_body

__all__ = ["WorkerConfig", "process_message_body"]
