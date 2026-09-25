"""Static contracts for the Raspberry Pi bootstrap and systemd appliance."""
from __future__ import annotations

import subprocess
import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = REPO_ROOT / "scripts" / "bootstrap_pi_inky.sh"
UNIT = REPO_ROOT / "ops" / "idle-hours.service.example"
APPLIANCE_CONFIG = REPO_ROOT / "idle_hours" / "assets" / "config.toml.example"


def test_bootstrap_is_valid_bash():
    subprocess.run(["bash", "-n", str(BOOTSTRAP)], check=True)


def test_bootstrap_installs_os_gpio_backend_and_exposes_it_to_venv():
    text = BOOTSTRAP.read_text(encoding="utf-8")
    assert "python3-lgpio" in text
    assert "python3-rpi-lgpio" in text
    assert "--system-site-packages" in text
    assert "import lgpio, RPi.GPIO" in text


def test_bootstrap_uses_spi_without_kernel_chip_select():
    text = BOOTSTRAP.read_text(encoding="utf-8")
    assert "do_spi 0" in text
    assert "dtoverlay=spi0-0cs" in text
    assert "/dev/spidev0.0" in text


def test_systemd_lgpio_runtime_stays_inside_state_directory():
    text = UNIT.read_text(encoding="utf-8")
    assert "WorkingDirectory=/var/lib/idle-hours" in text
    assert "Environment=LG_WD=/var/lib/idle-hours" in text
    assert "ReadWritePaths=%S/idle-hours" in text
    assert "/home/pi/IdleHours/output" not in text


def test_appliance_render_output_lives_in_state_directory():
    config = tomllib.loads(APPLIANCE_CONFIG.read_text(encoding="utf-8"))
    assert config["output"] == "/var/lib/idle-hours/current.png"
