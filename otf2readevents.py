from pathlib import Path
import runpy


runpy.run_path(
    str(Path(__file__).resolve().parent / "examples" / "python" / "otf2readevents.py"),
    run_name="__main__",
)