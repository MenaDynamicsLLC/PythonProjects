"""CLM Windows Diagnostics & Cleanup graphical front end.

The GUI stays intentionally thin: PowerShell remains the maintained diagnostics
engine so the commands are still readable and learnable.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, scrolledtext, ttk


APP_TITLE = "CLM Windows Diagnostics & Cleanup"
SCRIPT_NAME = "CLM-Windows-Diagnostics.ps1"


def powershell_script() -> Path:
    """Prefer the inspectable PS1 beside the EXE; fall back to the bundled copy."""
    if getattr(sys, "frozen", False):
        external = Path(sys.executable).resolve().with_name(SCRIPT_NAME)
        if external.exists():
            return external
        bundle_root = Path(getattr(sys, "_MEIPASS"))
        return bundle_root / SCRIPT_NAME
    return Path(__file__).resolve().with_name(SCRIPT_NAME)


def run_powershell(action: str, confirm_cleanup: bool = False) -> tuple[int, str]:
    """Run one named PowerShell action and return (exit_code, combined_output)."""
    script = powershell_script()
    if not script.exists():
        return 2, f"PowerShell engine not found: {script}"

    command = [
        "powershell.exe",
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
        "-Action",
        action,
    ]
    if confirm_cleanup:
        command.append("-ConfirmCleanup")

    creationflags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            errors="replace",
            creationflags=creationflags,
            check=False,
        )
    except OSError as exc:
        return 1, f"Unable to start PowerShell: {exc}"

    parts = [part.strip() for part in (completed.stdout, completed.stderr) if part and part.strip()]
    output = "\n\n".join(parts) if parts else "(Action completed with no text output.)"
    return completed.returncode, output


class CLMApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_TITLE)
        self.geometry("980x680")
        self.minsize(820, 560)

        self.status_var = tk.StringVar(value="Ready")
        self._buttons: list[ttk.Button] = []

        self._build_ui()

    def _build_ui(self) -> None:
        outer = ttk.Frame(self, padding=12)
        outer.pack(fill="both", expand=True)

        heading = ttk.Frame(outer)
        heading.pack(fill="x", pady=(0, 10))
        ttk.Label(
            heading,
            text=APP_TITLE,
            font=("Segoe UI", 16, "bold"),
        ).pack(anchor="w")
        ttk.Label(
            heading,
            text="Learning Edition 1.2 — PowerShell engine with a Windows GUI",
        ).pack(anchor="w", pady=(2, 0))

        body = ttk.Panedwindow(outer, orient="horizontal")
        body.pack(fill="both", expand=True)

        controls = ttk.Frame(body, padding=(0, 0, 12, 0))
        output_frame = ttk.Frame(body)
        body.add(controls, weight=0)
        body.add(output_frame, weight=1)

        ttk.Label(controls, text="Actions", font=("Segoe UI", 11, "bold")).pack(anchor="w", pady=(0, 8))

        actions = [
            ("RAM / System", lambda: self.run_action("System", "RAM / system information")),
            ("Memory Users", lambda: self.run_action("Memory", "biggest memory users")),
            ("Startup Programs", lambda: self.run_action("Startup", "startup programs")),
            ("Open Startup Apps", lambda: self.run_action("OpenStartup", "Windows Startup Apps")),
            ("TEMP Cleanup", self.preview_cleanup),
            ("Run All Diagnostics", lambda: self.run_action("Diagnostics", "all diagnostics")),
            ("Save Desktop Report", lambda: self.run_action("Report", "Desktop report")),
        ]

        for label, command in actions:
            button = ttk.Button(controls, text=label, command=command, width=24)
            button.pack(fill="x", pady=3)
            self._buttons.append(button)

        ttk.Separator(controls).pack(fill="x", pady=12)
        ttk.Button(controls, text="Clear Output", command=self.clear_output, width=24).pack(fill="x", pady=3)
        ttk.Button(controls, text="Exit", command=self.destroy, width=24).pack(fill="x", pady=3)

        ttk.Label(output_frame, text="Output", font=("Segoe UI", 11, "bold")).pack(anchor="w", pady=(0, 6))
        self.output = scrolledtext.ScrolledText(
            output_frame,
            wrap="word",
            font=("Consolas", 10),
            state="disabled",
        )
        self.output.pack(fill="both", expand=True)

        status = ttk.Label(outer, textvariable=self.status_var, anchor="w")
        status.pack(fill="x", pady=(8, 0))

        self.write_output(
            "CLM is ready.\n\n"
            "This GUI does not disable services, edit the registry, remove software, "
            "or change Windows Security settings. TEMP cleanup always previews eligible "
            "files before deletion."
        )

    def set_busy(self, busy: bool, message: str | None = None) -> None:
        state = "disabled" if busy else "normal"
        for button in self._buttons:
            button.configure(state=state)
        if message is not None:
            self.status_var.set(message)

    def write_output(self, text: str, replace: bool = False) -> None:
        self.output.configure(state="normal")
        if replace:
            self.output.delete("1.0", "end")
        self.output.insert("end", text.rstrip() + "\n")
        self.output.see("end")
        self.output.configure(state="disabled")

    def clear_output(self) -> None:
        self.output.configure(state="normal")
        self.output.delete("1.0", "end")
        self.output.configure(state="disabled")
        self.status_var.set("Ready")

    def run_action(self, action: str, label: str, confirm_cleanup: bool = False) -> None:
        self.set_busy(True, f"Running {label}...")
        self.write_output(f"\n=== {label.upper()} ===")

        def worker() -> None:
            code, text = run_powershell(action, confirm_cleanup=confirm_cleanup)
            self.after(0, self._finish_action, code, text, label)

        threading.Thread(target=worker, daemon=True).start()

    def _finish_action(self, code: int, text: str, label: str) -> None:
        self.write_output(text)
        if code == 0:
            self.status_var.set(f"Completed: {label}")
        else:
            self.status_var.set(f"Failed: {label} (exit code {code})")
            messagebox.showerror(APP_TITLE, f"{label} failed.\n\n{text}")
        self.set_busy(False)

    def preview_cleanup(self) -> None:
        self.set_busy(True, "Previewing eligible TEMP files...")
        self.write_output("\n=== TEMP CLEANUP PREVIEW ===")

        def worker() -> None:
            code, text = run_powershell("CleanupPreview")
            self.after(0, self._finish_cleanup_preview, code, text)

        threading.Thread(target=worker, daemon=True).start()

    def _finish_cleanup_preview(self, code: int, text: str) -> None:
        self.write_output(text)
        if code != 0:
            self.status_var.set(f"Cleanup preview failed (exit code {code})")
            self.set_busy(False)
            messagebox.showerror(APP_TITLE, f"Cleanup preview failed.\n\n{text}")
            return

        if "No eligible files." in text:
            self.status_var.set("Cleanup preview complete: nothing eligible")
            self.set_busy(False)
            return

        self.status_var.set("Cleanup preview complete")
        confirm = messagebox.askyesno(
            APP_TITLE,
            "Delete the eligible files shown in the preview?\n\n"
            "Deletion is permanent and does not use the Recycle Bin. "
            "The PowerShell engine revalidates each file before deleting it.",
        )
        self.set_busy(False)
        if confirm:
            self.run_action("Cleanup", "TEMP cleanup", confirm_cleanup=True)


def main() -> int:
    if os.name != "nt":
        messagebox.showerror(APP_TITLE, "This application requires Windows.")
        return 1

    script = powershell_script()
    if not script.exists():
        messagebox.showerror(APP_TITLE, f"Required PowerShell engine not found:\n{script}")
        return 2

    app = CLMApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
