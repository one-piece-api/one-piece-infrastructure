#!/usr/bin/env bash
# Port-forward verso i servizi del namespace auth, condiviso dai test.
# Va incluso con "source" dopo common.sh; chi lo include dichiara PF_PIDS=()
# e termina i PID in PF_PIDS nel proprio trap di uscita.

# start_port_forward <service> <local:remote> <logfile>
# kubectl port-forward a volte fallisce con "address already in use" se la
# porta locale è appena stata rilasciata da un run precedente (TIME_WAIT):
# un paio di retry con una breve pausa risolvono senza intervento manuale.
start_port_forward() {
  local service="$1" ports="$2" logfile="$3" attempt
  for attempt in 1 2 3; do
    kubectl port-forward "svc/$service" -n "$NAMESPACE" "$ports" >"$logfile" 2>&1 &
    local pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      grep -q "Forwarding from" "$logfile" 2>/dev/null && { PF_PIDS+=("$pid"); return 0; }
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
  done
  error "impossibile avviare 'kubectl port-forward svc/$service $ports' dopo 3 tentativi"
  cat "$logfile" >&2
  exit 1
}
