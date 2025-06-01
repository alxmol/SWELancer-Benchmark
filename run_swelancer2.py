from __future__ import annotations

# Load environment before importing anything else
from dotenv import load_dotenv
load_dotenv()

import logging
import sys
import pathlib
import datetime as dt
import os

from swelancer import SWELancerEval 
import argparse
import nanoeval
from nanoeval.evaluation import EvalSpec, RunnerArgs
from nanoeval.recorder import dummy_recorder
from nanoeval.setup import nanoeval_entrypoint
from swelancer_agent import SimpleAgentSolver

def setup_logging():
    log_dir = pathlib.Path("run_logs")
    log_dir.mkdir(exist_ok=True)
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    # Incorporate PID into log filename for multiprocessing safety
    log_path = log_dir / f"swelancer_{timestamp}_pid{os.getpid()}.log"
    handlers = [
        logging.FileHandler(log_path, mode="w"),
        logging.StreamHandler(sys.stdout), # keep console echoes
    ]

    # File handler logs everything; stream handler is more conservative
    handlers[0].setLevel(logging.INFO)
    handlers[1].setLevel(logging.WARNING)

    # Configure basic logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-8s %(name)-25s %(process)d --- [%(threadName)-12s] %(message)s",
        handlers=handlers,
        force=True # Force override if already configured by a library
    )

    # Configure structlog to use standard logging
    import structlog
    structlog.configure(
        processors=[
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )
    return log_path

def parse_args():
    parser = argparse.ArgumentParser(description='Run SWELancer evaluation')
    parser.add_argument('--issue_ids', nargs='*', type=str, help='List of ISSUE_IDs to evaluate. If not specified, all issues will be evaluated.')
    return parser.parse_args()

async def main() -> None:
    log_file_path = setup_logging()
    # Get the root logger
    root_logger = logging.getLogger()
    root_logger.info(f"Logging to file: {log_file_path}")

    args = parse_args()
    taskset = args.issue_ids if args.issue_ids else None

    report = await nanoeval.run(
        EvalSpec(
            # taskset is a list of ISSUE_IDs you wish to evaluate (e.g., ["123", "456_789"])
            eval=SWELancerEval(
                solver=SimpleAgentSolver(model="gpt-4o"),
                taskset=taskset
            ),
            runner=RunnerArgs(
                concurrency=25,
                experimental_use_multiprocessing=True,
                enable_slackbot=False,
                recorder=dummy_recorder(),
                max_retries=5
            ),
        )
    )
    print(report)


if __name__ == "__main__":
    nanoeval_entrypoint(main())
