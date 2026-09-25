#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="${HOME}/.virtualenvs/pimoroni"
BOOT_CONFIG="/boot/firmware/config.txt"

echo "==> Updating apt package lists"
sudo apt update

echo "==> Installing Raspberry Pi runtime dependencies"
sudo apt install -y \
  git gpiod python3 python3-dev python3-pip python3-venv \
  python3-lgpio python3-rpi-lgpio fonts-noto-core fonts-dejavu-core

if [ ! -f "${BOOT_CONFIG}" ]; then
  echo "Expected Raspberry Pi boot config at ${BOOT_CONFIG}" >&2
  exit 1
fi

echo "==> Configuring I2C and SPI for Inky Spectra 6"
sudo raspi-config nonint do_i2c 0
sudo raspi-config nonint do_spi 0
# The E673 driver opens /dev/spidev0.0 for data but drives GPIO8 chip-select
# itself. Ordinary SPI claims GPIO8 in the kernel; spi0-0cs exposes the bus
# without claiming any chip-select pins.
if ! grep -qx 'dtoverlay=spi0-0cs' "${BOOT_CONFIG}"; then
  printf '%s\n' 'dtoverlay=spi0-0cs' | sudo tee -a "${BOOT_CONFIG}" >/dev/null
fi

if [ "${CONTINUE_AFTER_REBOOT:-0}" != "1" ]; then
  printf '%s\n' \
    "==> Boot configuration staged." \
    "Reboot, then continue with:" \
    "  CONTINUE_AFTER_REBOOT=1 ./scripts/bootstrap_pi_inky.sh"
  exit 0
fi

if [ ! -c /dev/spidev0.0 ]; then
  echo "/dev/spidev0.0 is missing after reboot; check dtparam=spi=on and dtoverlay=spi0-0cs" >&2
  exit 1
fi
if gpioinfo 2>/dev/null | grep -E 'line[[:space:]]+8:' | grep -q 'consumer='; then
  echo "GPIO8 is still claimed; the E673 driver requires manual chip select via spi0-0cs" >&2
  exit 1
fi

echo "==> Creating the Pi virtualenv with Raspberry Pi OS GPIO bindings"
mkdir -p "$(dirname "${VENV_DIR}")"
if [ ! -d "${VENV_DIR}" ]; then
  python3 -m venv --system-site-packages "${VENV_DIR}"
fi
"${VENV_DIR}/bin/python" -c 'import lgpio, RPi.GPIO; print("GPIO backend: ok")'

cd "${REPO_DIR}"

echo "==> Installing the package (editable, with the Pi extra)"
"${VENV_DIR}/bin/pip" install -e ".[pi]"

echo "==> Rendering once"
"${VENV_DIR}/bin/idle-hours" run --once --buttons-off

echo "==> Attempting first display push"
"${VENV_DIR}/bin/idle-hours" display output/current.png

echo
printf '%s\n' "==> Optional: install systemd unit" \
  "The sample unit at ops/idle-hours.service.example uses Type=notify + WatchdogSec," \
  "StateDirectory=idle-hours (creates /var/lib/idle-hours), and a modest sandbox." \
  "To install:" \
  "  sudo install -d -o pi -g pi -m 0750 /var/lib/idle-hours" \
  "  sudo install -o pi -g pi -m 0640 idle_hours/assets/config.toml.example /var/lib/idle-hours/config.toml" \
  "  sudo cp ops/idle-hours.service.example /etc/systemd/system/idle-hours.service" \
  "  sudo systemctl daemon-reload" \
  "  sudo systemctl enable --now idle-hours.service" \
  "  systemctl status idle-hours.service  # should show Active: active (running); notify" \
  "" \
  "Migrating state from ~/.idle-hours/ to /var/lib/idle-hours/ (if needed) is documented" \
  "in docs/pi_setup_inky_impression.md under 'Migrating from ~/.idle-hours/'."
