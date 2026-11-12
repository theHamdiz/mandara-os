# Mandara OS recipes (ujust <recipe>).

# Go back to the Mandara version that came with the OS image (drops self-updates)
mandara-reset-shell:
    #!/usr/bin/bash
    set -euo pipefail
    rm -f /var/lib/mandara/bin/mandara /var/lib/mandara/bin/mandara.old /var/lib/mandara/bin/.seeded-from
    echo "Mandara $(cat /usr/lib/mandara/VERSION) from the OS image starts next time (log out, or: mandara msg restart)."

# Make /usr writable until the next reboot, for quick experiments
mandara-unlock-os:
    #!/usr/bin/bash
    set -euo pipefail
    sudo bootc usr-overlay
    echo "/usr is writable until you reboot. To keep a change, add it to the image instead."

# Docker API: "engine" runs Docker itself, "podman" points docker at rootless Podman
mandara-enable-docker mode="engine":
    #!/usr/bin/bash
    set -euo pipefail
    envfile="$HOME/.config/environment.d/50-docker-host.conf"
    case "{{ mode }}" in
    engine)
        rm -f "$envfile"
        sudo systemctl enable --now docker.socket
        # On image-based systems the docker group starts out in /usr/lib/group.
        if ! grep -q '^docker:' /etc/group; then
            grep '^docker:' /usr/lib/group | sudo tee -a /etc/group >/dev/null
        fi
        sudo usermod -aG docker "$USER"
        echo "Docker Engine is on. Log out and back in to use it without sudo."
        ;;
    podman)
        sudo systemctl disable --now docker.service docker.socket 2>/dev/null || true
        systemctl --user enable --now podman.socket
        mkdir -p "$(dirname "$envfile")"
        echo "DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/podman/podman.sock" > "$envfile"
        echo "docker now talks to rootless Podman. Log out and back in to apply DOCKER_HOST."
        ;;
    *)
        echo "Usage: ujust mandara-enable-docker [engine|podman]" >&2
        exit 1
        ;;
    esac
