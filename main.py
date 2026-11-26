#!/usr/bin/env python3
"""
HostScripts - Interactive script browser and launcher.

Run:
    python3 main.py
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import PurePosixPath
from typing import Optional

try:
    from rich.console import Console
    from rich.markdown import Markdown
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text
    from rich.prompt import Confirm, Prompt
except ImportError:
    print("Missing dependency: python3-rich")
    print("Install project dependencies first: sudo bash depends.sh")
    raise SystemExit(1)


REPOSITORY = "flyingaura-git/HostScripts"
BRANCH = "main"
SCRIPTS_PATH = "scripts"
API_BASE = f"https://api.github.com/repos/{REPOSITORY}"
RAW_BASE = f"https://raw.githubusercontent.com/{REPOSITORY}"
USER_AGENT = "HostScripts-CLI/1.0"
SUPPORTED_SCRIPTS = {".sh", ".bash", ".py"}
console = Console()


@dataclass
class Script:
    name: str
    path: str
    metadata: dict = field(default_factory=dict)

    @property
    def description(self) -> str:
        return self.metadata.get("description", "No description provided.")

    @property
    def symbol(self) -> str:
        return self.metadata.get("symbol", "📄")


@dataclass
class Category:
    name: str
    path: str
    metadata: dict = field(default_factory=dict)
    categories: list["Category"] = field(default_factory=list)
    scripts: list[Script] = field(default_factory=list)

    @property
    def title(self) -> str:
        return self.metadata.get("name", self.name.replace("-", " ").replace("_", " ").title())

    @property
    def description(self) -> str:
        return self.metadata.get("description", "No description provided.")

    @property
    def symbol(self) -> str:
        return self.metadata.get("symbol", "📁")

    @property
    def featured(self) -> bool:
        return str(self.metadata.get("featured", "false")).lower() in {"true", "yes", "1"}


def request_text(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(request, timeout=25) as response:
        return response.read().decode("utf-8")


def request_json(url: str):
    return json.loads(request_text(url))


def parse_metadata(markdown_text: str) -> tuple[dict, str]:
    """Read simple YAML-style frontmatter without requiring PyYAML."""
    if not markdown_text.startswith("---"):
        return {}, markdown_text.strip()

    parts = markdown_text.split("---", 2)
    if len(parts) < 3:
        return {}, markdown_text.strip()

    metadata = {}
    for line in parts[1].splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        value = value.strip().strip('"').strip("'")
        metadata[key.strip().lower()] = value

    return metadata, parts[2].strip()


def fetch_optional_markdown(path: str) -> tuple[dict, str]:
    url = f"{RAW_BASE}/{COMMIT_SHA}/{path}"
    try:
        return parse_metadata(request_text(url))
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
        return {}, ""


def fetch_script_metadata(path: str) -> dict:
    candidates = [f"{path}.md"]
    stem = str(PurePosixPath(path).with_suffix(""))
    if f"{stem}.md" not in candidates:
        candidates.append(f"{stem}.md")

    for candidate in candidates:
        metadata, body = fetch_optional_markdown(candidate)
        if metadata or body:
            metadata["_body"] = body
            return metadata
    return {}


def build_tree(entries: list[dict]) -> list[Category]:
    """Build an unlimited-depth category tree from the Git tree response."""
    directories: dict[str, Category] = {}
    files_by_parent: dict[str, list[dict]] = {}

    for entry in entries:
        path = entry.get("path", "")
        if not path.startswith(SCRIPTS_PATH + "/"):
            continue

        relative = path[len(SCRIPTS_PATH) + 1:]
        parent = str(PurePosixPath(relative).parent)
        if parent == ".":
            parent = ""

        if entry.get("type") == "tree":
            name = PurePosixPath(relative).name
            directories[relative] = Category(name=name, path=path)
        elif entry.get("type") == "blob":
            files_by_parent.setdefault(parent, []).append(entry)

    # Load category metadata.
    for relative, category in directories.items():
        category.metadata, _ = fetch_optional_markdown(f"{category.path}/category.md")

    # Attach each directory to its parent, or to the root.
    roots: list[Category] = []
    for relative, category in sorted(directories.items()):
        parent = str(PurePosixPath(relative).parent)
        if parent == ".":
            roots.append(category)
        elif parent in directories:
            directories[parent].categories.append(category)

    # Attach runnable scripts to their containing category.
    for parent, files in files_by_parent.items():
        if not parent or parent not in directories:
            continue
        category = directories[parent]
        for entry in files:
            filename = PurePosixPath(entry["path"]).name
            suffix = PurePosixPath(filename).suffix.lower()
            if suffix not in SUPPORTED_SCRIPTS or filename.startswith("_"):
                continue
            category.scripts.append(
                Script(
                    name=PurePosixPath(filename).stem.replace("-", " ").replace("_", " ").title(),
                    path=entry["path"],
                    metadata=fetch_script_metadata(entry["path"]),
                )
            )

    def sort_category(category: Category):
        category.categories.sort(key=lambda item: item.title.lower())
        category.scripts.sort(key=lambda item: item.name.lower())
        for child in category.categories:
            sort_category(child)

    for root in roots:
        sort_category(root)

    return sorted(roots, key=lambda item: (not item.featured, item.title.lower()))


def category_count(category: Category) -> int:
    return len(category.categories) + sum(category_count(child) for child in category.categories)


def script_count(category: Category) -> int:
    return len(category.scripts) + sum(script_count(child) for child in category.categories)


def show_header():
    console.print()
    console.print(
        Panel.fit(
            Text("HOSTSCRIPTS", style="bold bright_white", justify="center")
            + Text("\nYour hosting scripts command center", style="cyan"),
            border_style="bright_magenta",
            padding=(1, 5),
        )
    )


def choose_from_list(title: str, options: list, label_func, back_label: str = "Back"):
    if not options:
        console.print("[yellow]Nothing to display here yet.[/yellow]")
        Prompt.ask("Press Enter to continue", default="")
        return None

    console.print(f"\n[bold bright_cyan]{title}[/bold bright_cyan]")
    for index, option in enumerate(options, 1):
        console.print(f"  [bold yellow]{index:>2}.[/bold yellow] {label_func(option)}")
    console.print(f"  [dim]0. {back_label}[/dim]")

    while True:
        choice = Prompt.ask("Select", default="0").strip()
        if choice == "0":
            return None
        if choice.isdigit() and 1 <= int(choice) <= len(options):
            return options[int(choice) - 1]
        console.print("[red]Invalid selection. Try again.[/red]")


def show_category(category: Category):
    while True:
        console.clear()
        show_header()
        console.print(
            Panel(
                f"[bold]{category.symbol}  {category.title}[/bold]\n{category.description}",
                border_style="cyan",
            )
        )

        options = []
        for child in category.categories:
            options.append(("category", child))
        for script in category.scripts:
            options.append(("script", script))

        selected = choose_from_list(
            "CATEGORY CONTENTS",
            options,
            lambda item: (
                f"[cyan]{item[1].symbol}  {item[1].title}[/cyan]  [dim]{item[1].description}[/dim]"
                if item[0] == "category"
                else f"[green]{item[1].symbol}  {item[1].name}[/green]  [dim]{item[1].description}[/dim]"
            ),
        )
        if selected is None:
            return
        kind, item = selected
        if kind == "category":
            show_category(item)
        else:
            show_script(item)


def show_script(script: Script):
    console.clear()
    show_header()

    details = script.metadata.get("_body", "")
    description = script.description
    if details:
        description = f"{description}\n\n{details}"

    console.print(
        Panel(
            f"[bold bright_white]{script.symbol}  {script.name}[/bold bright_white]\n"
            f"[dim]{script.path}[/dim]\n\n{description}",
            title="SCRIPT INFORMATION",
            border_style="green",
        )
    )

    console.print("[bold]Execution details[/bold]")
    console.print(f"  File type: [cyan]{PurePosixPath(script.path).suffix}[/cyan]")
    console.print("  Source: [link]" + f"https://github.com/{REPOSITORY}/blob/{COMMIT_SHA}/{script.path}" + "[/link]")

    if not Confirm.ask("\nDo you want to run this script?", default=False):
        return

    run_script(script)


def run_script(script: Script):
    suffix = PurePosixPath(script.path).suffix.lower()
    url = f"{RAW_BASE}/{COMMIT_SHA}/{script.path}"

    try:
        console.print("\n[cyan]Downloading script...[/cyan]")
        content = request_text(url)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as error:
        console.print(f"[red]Could not download script: {error}[/red]")
        Prompt.ask("Press Enter to continue", default="")
        return

    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", suffix=suffix, delete=False
        ) as temporary:
            temporary.write(content)
            temporary_path = temporary.name

        if suffix in {".sh", ".bash"}:
            command = ["bash", temporary_path]
        elif suffix == ".py":
            command = [sys.executable, temporary_path]
        else:
            console.print("[red]This script type is not supported for execution.[/red]")
            return

        console.print(
            Panel(
                f"[yellow]{' '.join(command)}[/yellow]\n"
                "[dim]The script will run with your current user's permissions.[/dim]",
                title="CONFIRM EXECUTION",
                border_style="yellow",
            )
        )
        if not Confirm.ask("Proceed?", default=False):
            return

        result = subprocess.run(command, check=False)
        if result.returncode == 0:
            console.print("\n[bold green]Script completed successfully.[/bold green]")
        else:
            console.print(f"\n[bold red]Script exited with code {result.returncode}.[/bold red]")
        Prompt.ask("Press Enter to continue", default="")
    except KeyboardInterrupt:
        console.print("\n[yellow]Execution interrupted.[/yellow]")
    finally:
        try:
            os.unlink(temporary_path)
        except (OSError, UnboundLocalError):
            pass


def flatten_scripts(categories: list[Category]) -> list[Script]:
    found = []
    for category in categories:
        found.extend(category.scripts)
        found.extend(flatten_scripts(category.categories))
    return found


def search_scripts(categories: list[Category]):
    all_scripts = flatten_scripts(categories)
    while True:
        console.clear()
        show_header()
        query = Prompt.ask("Search scripts (leave empty to go back)").strip().lower()
        if not query:
            return

        matches = [
            script for script in all_scripts
            if query in script.name.lower()
            or query in script.path.lower()
            or query in script.description.lower()
        ]
        if not matches:
            console.print("[yellow]No matching scripts found.[/yellow]")
            Prompt.ask("Press Enter to search again", default="")
            continue

        selected = choose_from_list(
            f"SEARCH RESULTS ({len(matches)})",
            matches,
            lambda item: f"[green]{item.symbol}  {item.name}[/green]  [dim]{item.path}[/dim]",
        )
        if selected is None:
            continue
        show_script(selected)


def show_top_picks(categories: list[Category]):
    console.clear()
    show_header()
    featured = [category for category in categories if category.featured]
    picks = featured or categories
    console.print("[bold bright_cyan]TOP PICKS[/bold bright_cyan]")
    console.print("[dim]Main script categories[/dim]\n")

    table = Table(show_header=True, header_style="bold magenta")
    table.add_column("#", style="yellow", width=3)
    table.add_column("Category")
    table.add_column("Description")
    table.add_column("Scripts", justify="right")
    for index, category in enumerate(picks, 1):
        table.add_row(
            str(index),
            f"{category.symbol}  {category.title}",
            category.description,
            str(script_count(category)),
        )
    console.print(table)

    selected = choose_from_list(
        "OPEN A CATEGORY",
        picks,
        lambda item: f"{item.symbol}  {item.title}  [dim]({script_count(item)} scripts)[/dim]",
    )
    if selected:
        show_category(selected)


def main():
    global COMMIT_SHA

    console.clear()
    show_header()
    try:
        console.print("[cyan]Connecting to HostScripts repository...[/cyan]")
        branch_data = request_json(f"{API_BASE}/branches/{BRANCH}")
        COMMIT_SHA = branch_data["commit"]["sha"]
        tree_data = request_json(
            f"{API_BASE}/git/trees/{COMMIT_SHA}?recursive=1"
        )
        if tree_data.get("truncated"):
            raise RuntimeError("GitHub returned a truncated repository tree.")

        categories = build_tree(tree_data.get("tree", []))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, KeyError, ValueError, RuntimeError) as error:
        console.print(f"\n[bold red]Could not load HostScripts: {error}[/bold red]")
        raise SystemExit(1)

    total_scripts = sum(script_count(category) for category in categories)
    console.clear()

    while True:
        show_header()
        console.print(
            f"[dim]{len(categories)} main categories  •  {total_scripts} scripts discovered[/dim]\n"
        )
        console.print("[bold bright_cyan]HOME[/bold bright_cyan]")
        console.print("  [yellow]1.[/yellow] ⭐ Top Picks")
        console.print("  [yellow]2.[/yellow] 📂 Browse all categories")
        console.print("  [yellow]3.[/yellow] 🔎 Search scripts")
        console.print("  [yellow]4.[/yellow] 🔄 Refresh repository")
        console.print("  [dim]0. Exit[/dim]")

        choice = Prompt.ask("Select", default="1").strip()
        if choice == "0":
            console.print("[cyan]Thanks for using HostScripts.[/cyan]")
            return
        if choice == "1":
            show_top_picks(categories)
        elif choice == "2":
            selected = choose_from_list(
                "ALL CATEGORIES",
                categories,
                lambda item: f"{item.symbol}  {item.title}  [dim]({script_count(item)} scripts)[/dim]",
            )
            if selected:
                show_category(selected)
        elif choice == "3":
            search_scripts(categories)
        elif choice == "4":
            main()
            return
        else:
            console.print("[red]Invalid selection.[/red]")


if __name__ == "__main__":
    main()
