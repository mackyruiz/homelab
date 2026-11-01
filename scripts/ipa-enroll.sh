#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/ipa-enroll.sh [options] [TARGET] [-- ansible-playbook args...]

Enroll hosts in FreeIPA (freeipa.example.com) and restrict IPA SSH logins to keys/Kerberos.

TARGET        Inventory host, group, or pattern (default: ipa_clients), or the
              name/FQDN of a new host that is not in ansible/inventory/hosts.yml yet.
--ip ADDR     Connect to ADDR instead of the inventory address (single host only).
--user USER   SSH user for the connection (default: inventory ansible_user, labadmin).
--fqdn FQDN   Enroll under this FQDN (single host only; default: TARGET or TARGET.example.com).
--check       Dry run (--check --diff).
-h, --help    Show this help.

Examples:
  scripts/ipa-enroll.sh                              # every host in ipa_clients
  scripts/ipa-enroll.sh pis                          # one group
  scripts/ipa-enroll.sh labtest --ip 10.0.0.50    # inventory host, address from Terraform
  scripts/ipa-enroll.sh pi5.example.com --user ubuntu -- -K   # brand-new host, ask sudo password
EOF
}

usage_error() {
  echo "error: $1" >&2
  usage >&2
  exit 2
}

cd "$(dirname "$(readlink -f "$0")")/../ansible"

target=""
ip=""
user=""
fqdn=""
check=0
passthru=()

while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --ip|--user|--fqdn)
      (($# >= 2)) || usage_error "$1 needs a value"
      case "$1" in
        --ip) ip=$2 ;;
        --user) user=$2 ;;
        --fqdn) fqdn=$2 ;;
      esac
      shift 2
      ;;
    --check) check=1; shift ;;
    --) shift; passthru=("$@"); break ;;
    -*) usage_error "unknown option $1" ;;
    *)
      [[ -z $target ]] || usage_error "only one TARGET allowed"
      target=$1
      shift
      ;;
  esac
done
target=${target:-ipa_clients}

inv=(-i inventory/hosts.yml)
count=$(ansible "$target" -i inventory/hosts.yml --list-hosts 2>/dev/null | sed -n 's/^ *hosts (\([0-9]*\)):$/\1/p' || true)
count=${count:-0}

if ((count == 0)); then
  if [[ $target == *[:,*\!\&\[\]~]* ]]; then
    echo "error: TARGET '$target' matches no inventory host" >&2
    exit 2
  fi
  inv+=(-i "$target,")
  count=1
  echo "note: $target is not in ansible/inventory/hosts.yml; add it under ipa_clients to keep it managed." >&2
fi

if [[ -n $ip || -n $fqdn ]] && ((count != 1)); then
  echo "error: --ip/--fqdn require TARGET to be a single host (matched $count)" >&2
  exit 2
fi

extra=(-e "ipa_enroll_target=$target")
[[ -z $ip ]] || extra+=(-e "ansible_host=$ip")
[[ -z $user ]] || extra+=(-e "ansible_user=$user")
[[ -z $fqdn ]] || extra+=(-e "ipa_client_fqdn=$fqdn")
((check == 0)) || extra+=(--check --diff)

exec ansible-playbook "${inv[@]}" playbooks/ipa_clients.yml "${extra[@]}" ${passthru[@]+"${passthru[@]}"}
