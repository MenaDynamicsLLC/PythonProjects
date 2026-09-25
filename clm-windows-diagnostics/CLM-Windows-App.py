"""CLM Windows Toolkit graphical front end.

PowerShell remains the inspectable diagnostics engine. The GUI only invokes
named actions and displays their output.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, scrolledtext, ttk


APP_TITLE = "CLM Windows Toolkit"
APP_VERSION = "2.0.0"
PUBLISHER = "Mena Dynamics, LLC"
SCRIPT_NAME = "CLM-Windows-Diagnostics.ps1"
AUDIT_NAME = "CLM-Audit.ps1"
ICON_NAME = "clm-toolkit.ico"


def resource_file(name: str) -> Path:
    """Find a file beside the EXE first, then inside the PyInstaller bundle."""
    if getattr(sys, "frozen", False):
        external = Path(sys.executable).resolve().with_name(name)
        if external.exists():
            return external
        return Path(getattr(sys, "_MEIPASS")) / name
    return Path(__file__).resolve().with_name(name)


def powershell_runtime() -> tuple[Path, Path]:
    """Use an external engine only when both inspectable PowerShell files are present."""
    if getattr(sys, "frozen", False):
        external_dir = Path(sys.executable).resolve().parent
        external_script = external_dir / SCRIPT_NAME
        external_audit = external_dir / AUDIT_NAME
        if external_script.exists() and external_audit.exists():
            return external_script, external_audit
        bundle_dir = Path(getattr(sys, "_MEIPASS"))
        return bundle_dir / SCRIPT_NAME, bundle_dir / AUDIT_NAME
    source_dir = Path(__file__).resolve().parent
    return source_dir / SCRIPT_NAME, source_dir / AUDIT_NAME


def run_powershell(action: str, confirm_cleanup: bool = False) -> tuple[int, str]:
    script, audit = powershell_runtime()
    if not script.exists():
        return 2, f"PowerShell engine not found: {script}"
    if not audit.exists():
        return 2, f"Audit module not found: {audit}"

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
        self.title(f"{APP_TITLE} {APP_VERSION}")
        self.geometry("1120x760")
        self.minsize(940, 620)

        icon = resource_file(ICON_NAME)
        if icon.is_file():
            try:
                self.iconbitmap(default=str(icon))
            except tk.TclError:
                pass

        self.status_var = tk.StringVar(value="Ready")
        self._buttons: list[ttk.Button] = []
        self._build_ui()

    def _button(self, parent: ttk.Frame, label: str, action: str, description: str) -> None:
        button = ttk.Button(parent, text=label, command=lambda: self.run_action(action, description))
        button.pack(fill="x", pady=3)
        self._buttons.append(button)

    def _build_ui(self) -> None:
        outer = ttk.Frame(self, padding=12)
        outer.pack(fill="both", expand=True)

        heading = ttk.Frame(outer)
        heading.pack(fill="x", pady=(0, 10))
        ttk.Label(heading, text=APP_TITLE, font=("Segoe UI", 17, "bold")).pack(anchor="w")
        ttk.Label(
            heading,
            text=f"Version {APP_VERSION} — {PUBLISHER} • Health, performance, security and cleanup",
        ).pack(anchor="w", pady=(2, 0))

        body = ttk.Panedwindow(outer, orient="horizontal")
        body.pack(fill="both", expand=True)

        controls_host = ttk.Frame(body)
        output_frame = ttk.Frame(body)
        body.add(controls_host, weight=0)
        body.add(output_frame, weight=1)

        canvas = tk.Canvas(controls_host, width=265, highlightthickness=0)
        scroll = ttk.Scrollbar(controls_host, orient="vertical", command=canvas.yview)
        controls = ttk.Frame(canvas, padding=(0, 0, 10, 0))
        controls.bind("<Configure>", lambda _: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=controls, anchor="nw", width=250)
        canvas.configure(yscrollcommand=scroll.set)
        canvas.pack(side="left", fill="y", expand=False)
        scroll.pack(side="right", fill="y")

        ttk.Label(controls, text="Health & Performance", font=("Segoe UI", 10, "bold")).pack(anchor="w", pady=(0, 5))
        self._button(controls, "Health Summary", "Health", "health summary")
        self._button(controls, "System / RAM", "System", "system and RAM information")
        self._button(controls, "Performance Snapshot", "Performance", "performance snapshot")
        self._button(controls, "Memory Users", "Memory", "biggest memory users")
        self._button(controls, "Physical + Logical Disks", "Disks", "disk information")

        ttk.Separator(controls).pack(fill="x", pady=10)
        ttk.Label(controls, text="Security & Review", font=("Segoe UI", 10, "bold")).pack(anchor="w", pady=(0, 5))
        self._button(controls, "Startup Audit", "Startup", "startup audit")
        self._button(controls, "Security Status", "Security", "Defender and firewall status")
        self._button(controls, "Remote-Access Audit", "RemoteAccess", "remote-access audit")
        self._button(controls, "Optional Software Review", "SoftwareReview", "optional software review")
        self._button(controls, "Save Incident Snapshot", "Incident", "incident snapshot")

        ttk.Separator(controls).pack(fill="x", pady=10)
        ttk.Label(controls, text="Toolkit", font=("Segoe UI", 10, "bold")).pack(anchor="w", pady=(0, 5))
        self._button(controls, "Complete Audit", "Diagnostics", "complete health + security audit")
        self._button(controls, "Save Desktop Report", "Report", "Desktop report")
        self._button(controls, "Open Startup Apps", "OpenStartup", "Windows Startup Apps")

        cleanup = ttk.Button(controls, text="TEMP Cleanup", command=self.preview_cleanup)
        cleanup.pack(fill="x", pady=3)
        self._buttons.append(cleanup)

        ttk.Separator(controls).pack(fill="x", pady=10)
        ttk.Button(controls, text="Clear Output", command=self.clear_output).pack(fill="x", pady=3)
        ttk.Button(controls, text="Exit", command=self.destroy).pack(fill="x", pady=3)

        ttk.Label(output_frame, text="Output", font=("Segoe UI", 11, "bold")).pack(anchor="w", pady=(0, 6))
        self.output = scrolledtext.ScrolledText(
            output_frame,
            wrap="word",
            font=("Consolas", 10),
            state="disabled",
        )
        self.output.pack(fill="both", expand=True)

        ttk.Label(outer, textvariable=self.status_var, anchor="w").pack(fill="x", pady=(8, 0))

        self.write_output(
            "CLM Windows Toolkit 2.0 is ready.\n\n"
            "Diagnosis first: the toolkit does not automatically disable services, remove software, "
            "change firewall/security settings, or terminate remote-access tools. Findings marked "
            "REVIEW need a human decision. TEMP cleanup previews eligible files before deletion."
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
            "The PowerShell engine re-checks eligibility immediately before deletion.",
        )
        self.set_busy(False)
        if confirm:
            self.run_action("Cleanup", "TEMP cleanup", confirm_cleanup=True)


def main() -> int:
    if os.name != "nt":
        messagebox.showerror(APP_TITLE, "This application requires Windows.")
        return 1

    script, audit = powershell_runtime()
    missing = [str(path) for path in (script, audit) if not path.exists()]
    if missing:
        messagebox.showerror(APP_TITLE, "Required toolkit file(s) not found:\n" + "\n".join(missing))
        return 2

    app = CLMApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
