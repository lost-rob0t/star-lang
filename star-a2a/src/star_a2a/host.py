from __future__ import annotations

import asyncio
import json
import threading
from collections import defaultdict
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pykka
from a2a.helpers import get_message_text, new_task_from_user_message, new_text_message, new_text_part
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore, TaskUpdater
from a2a.types import AgentCapabilities, AgentCard, AgentInterface, AgentSkill
from a2a.types.a2a_pb2 import TaskState
from a2a.utils.constants import AGENT_CARD_WELL_KNOWN_PATH
from starlette.applications import Starlette

EXPECTED_WORKERS = {
    "beast-orchestrator",
    "gov-catalog",
    "gov-harvester",
    "challenge-broker",
    "proxy-egress",
    "recon-domain",
    "normalize-provenance",
    "archive-preserve",
    "corroborate-verify",
    "graph-index-publisher",
}

Delegate = Callable[[str, str], Awaitable[dict[str, Any]]]


@dataclass(slots=True)
class InvocationState:
    counts: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    last_input: dict[str, str] = field(default_factory=dict)
    actor_refs: dict[str, pykka.ActorRef[Any]] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def record(self, worker_id: str, text: str) -> None:
        with self._lock:
            self.counts[worker_id] += 1
            self.last_input[worker_id] = text

    def register_actor(self, worker_id: str, actor_ref: pykka.ActorRef[Any]) -> None:
        if worker_id in self.actor_refs:
            raise ValueError(f"duplicate worker actor: {worker_id}")
        self.actor_refs[worker_id] = actor_ref

    def stop_workers(self) -> None:
        refs = list(self.actor_refs.values())
        self.actor_refs.clear()
        for actor_ref in refs:
            actor_ref.stop(block=True, timeout=5)


class ReferenceWorkerActor(pykka.ThreadingActor):
    """One bounded-mailbox execution identity behind one public A2A endpoint.

    Production deployments can replace this reference actor with domain-specific
    implementations while preserving the same StarLang/A2A contract. Inter-worker
    coordination remains A2A; Pykka owns the local worker mailbox/lifecycle only.
    """

    def __init__(self, worker_id: str, state: InvocationState) -> None:
        super().__init__()
        self.worker_id = worker_id
        self.state = state

    def on_receive(self, message: Any) -> dict[str, Any]:
        if not isinstance(message, dict) or message.get("type") != "execute":
            raise ValueError("unsupported worker actor message")
        text = str(message.get("text") or "")
        self.state.record(self.worker_id, text)
        return {
            "worker": self.worker_id,
            "accepted": True,
            "input": text,
            "runtime": "pykka",
        }


def load_beast_catalog(path: str | Path) -> dict[str, Any]:
    catalog = json.loads(Path(path).read_text(encoding="utf-8"))
    if catalog.get("a2a_protocol") != "1.0.0":
        raise ValueError("Beast catalog must target A2A 1.0.0")
    if catalog.get("goal_documents") != 100_000_000:
        raise ValueError("Beast catalog corpus goal drifted")
    workers = catalog.get("workers")
    if not isinstance(workers, list):
        raise ValueError("Beast catalog workers must be a list")
    worker_ids = [worker.get("id") for worker in workers]
    if len(worker_ids) != len(set(worker_ids)):
        raise ValueError("duplicate Beast worker id")
    if set(worker_ids) != EXPECTED_WORKERS:
        raise ValueError("Beast catalog must contain the exact ten public workers")
    for worker in workers:
        if not worker.get("skills"):
            raise ValueError(f"{worker.get('id')}: at least one A2A skill is required")
        if not str(worker.get("star_uri", "")).startswith("star://starintel:beast:"):
            raise ValueError(f"{worker.get('id')}: invalid Star service URI")
    return catalog


def _worker_card(worker: dict[str, Any], path: str, public_url: str) -> AgentCard:
    skills = [
        AgentSkill(
            id=skill,
            name=skill.replace("-", " ").title(),
            description=f"StarIntel {worker['id']} capability: {skill}.",
            tags=["starintel", "star-lang", "beast-100m"],
            input_modes=["text/plain", "application/json"],
            output_modes=["text/plain", "application/json"],
            examples=[],
        )
        for skill in worker["skills"]
    ]
    return AgentCard(
        name=worker["id"],
        description=f"StarIntel Beast worker {worker['id']} ({worker['star_uri']}).",
        version="1.0.0",
        default_input_modes=["text/plain", "application/json"],
        default_output_modes=["text/plain", "application/json"],
        capabilities=AgentCapabilities(streaming=True),
        supported_interfaces=[
            AgentInterface(
                protocol_binding="JSONRPC",
                protocol_version="1.0",
                url=f"{public_url.rstrip('/')}{path}",
            )
        ],
        skills=skills,
    )


class ReferenceWorkerExecutor(AgentExecutor):
    def __init__(
        self,
        worker_id: str,
        actor_ref: pykka.ActorRef[Any],
        delegate: Delegate | None = None,
    ) -> None:
        self.worker_id = worker_id
        self.actor_ref = actor_ref
        self.delegate = delegate

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        task = context.current_task or new_task_from_user_message(context.message)
        if context.current_task is None:
            await event_queue.enqueue_event(task)

        updater = TaskUpdater(
            event_queue=event_queue,
            task_id=task.id,
            context_id=task.context_id,
        )
        await updater.update_status(
            state=TaskState.TASK_STATE_WORKING,
            message=new_text_message(f"{self.worker_id}: accepted"),
        )

        text = get_message_text(context.message) or ""
        result = await asyncio.to_thread(
            lambda: self.actor_ref.ask(
                {"type": "execute", "text": text},
                block=True,
                timeout=10,
            )
        )
        if not isinstance(result, dict):
            raise TypeError("worker actor returned a non-object result")

        if self.worker_id == "beast-orchestrator" and self.delegate is not None:
            result["delegated"] = await self.delegate("gov-catalog", text)

        await updater.add_artifact(
            parts=[
                new_text_part(
                    text=json.dumps(result, sort_keys=True, separators=(",", ":")),
                    media_type="application/json",
                )
            ]
        )
        await updater.update_status(
            state=TaskState.TASK_STATE_COMPLETED,
            message=new_text_message(f"{self.worker_id}: completed"),
        )

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        if context.current_task is None:
            raise ValueError("cannot cancel a task that does not exist")
        updater = TaskUpdater(
            event_queue=event_queue,
            task_id=context.current_task.id,
            context_id=context.current_task.context_id,
        )
        await updater.update_status(state=TaskState.TASK_STATE_CANCELED)


def build_app(
    catalog: dict[str, Any],
    *,
    public_url: str,
    state: InvocationState | None = None,
    delegate: Delegate | None = None,
) -> tuple[Starlette, InvocationState]:
    runtime_state = state or InvocationState()
    routes = []

    try:
        for worker in catalog["workers"]:
            worker_id = worker["id"]
            path = f"/a2a/{worker_id}"
            card = _worker_card(worker, path, public_url)
            actor_ref = ReferenceWorkerActor.start(worker_id, runtime_state)
            runtime_state.register_actor(worker_id, actor_ref)
            executor = ReferenceWorkerExecutor(worker_id, actor_ref, delegate)
            handler = DefaultRequestHandler(
                agent_executor=executor,
                task_store=InMemoryTaskStore(),
                agent_card=card,
            )
            routes.extend(
                create_agent_card_routes(
                    card,
                    card_url=f"{path}{AGENT_CARD_WELL_KNOWN_PATH}",
                )
            )
            routes.extend(create_jsonrpc_routes(handler, rpc_url=path))
    except Exception:
        runtime_state.stop_workers()
        raise

    return Starlette(routes=routes), runtime_state
