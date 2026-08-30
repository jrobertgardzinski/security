#!/bin/bash
# Swap ONE service out of the Docker stack and run it from the IDE (or a terminal) against the
# rest — no image rebuild, no compose ceremony for a one-line change.
#
#   ./dev-swap.sh memes            stop the container, print what to paste into the IDE
#   ./dev-swap.sh run memes        same, then run the jar from target/ right here (Ctrl+C stops it)
#   ./dev-swap.sh back memes       start the container again
#
# The service on the host sees the stack through the ports the compose files publish (databases,
# MinIO, the encoder, Kafka's HOST listener on 29092, Mailpit's SMTP, sms/push), configured by the
# env file dev/local/<service>.env — the SAME variable names as the compose environment, so the
# service cannot tell where it runs. Every compose in the estate joins the "security" project,
# so the script is the same whichever workspace it lives in (portal/ links to this file).
#
# Containers dial the swappable services via host.docker.internal:<published port> (see the
# compose files), so a client cannot tell whether the service lives in Docker or in the IDE.
set -euo pipefail

usage() { sed -n '2,15p' "$0"; exit 1; }

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)     # ../shared, whichever link was called
case "${1:-}" in
    run|back) mode=$1; service=${2:-}; ;;
    "") usage ;;
    *) mode=swap; service=$1 ;;
esac
[ -n "$service" ] || usage

env_file=""
for dir in "$here/dev/local" "$here/../portal/dev/local" "$here/../formula/dev/local"; do
    if [ -f "$dir/$service.env" ]; then env_file=$(readlink -f "$dir/$service.env"); break; fi
done
[ -n "$env_file" ] || { echo "no dev/local/$service.env — services with one:"; ls "$here"/dev/local "$here"/../portal/dev/local 2>/dev/null | grep '\.env$' | sed 's/\.env$//' | sort -u | sed 's/^/  /'; exit 1; }

# where the executable jar lives, per service (relative to the workspace that owns it)
jar_of() {
    case "$1" in
        memes)            echo "$here/../portal/microservice-memes/memes-infrastructure/target/memes-infrastructure-1.0.0-SNAPSHOT.jar" ;;
        comments)         ls "$here"/../portal/microservice-comments/target/*.jar 2>/dev/null | grep -v -- '-sources\|original' | head -1 ;;
        user-collections) ls "$here"/../portal/microservice-user-collections/target/*.jar 2>/dev/null | grep -v -- '-sources\|original' | head -1 ;;
        offboarding)      ls "$here"/../portal/microservice-offboarding/target/*.jar 2>/dev/null | grep -v -- '-sources\|original' | head -1 ;;
        security)         echo "$here/microservice-security/security-infrastructure/target/security-infrastructure-1.0.0-SNAPSHOT.jar" ;;
        email)            echo "$here/microservice-email/target/quarkus-app/quarkus-run.jar" ;;
        *)                echo "" ;;
    esac
}

if [ "$mode" = back ]; then
    docker compose -p security start "$service"
    echo "$service is back in Docker"
    exit 0
fi

docker compose -p security stop "$service" >/dev/null
echo "container '$service' stopped — its port is free for the process you start now."
echo
echo "IDE: Run Configuration -> Environment variables -> paste (one line, IntelliJ splits it):"
grep -vE '^\s*(#|$)' "$env_file" | paste -sd ';'
echo
echo "or the file itself (EnvFile plugin / 'Load from file'): $env_file"
echo "terminal:  ./dev-swap.sh run $service      back in Docker:  ./dev-swap.sh back $service"

if [ "$mode" = run ]; then
    jar=$(jar_of "$service")
    [ -n "$jar" ] && [ -f "$jar" ] || { echo; echo "no jar for $service — build it first (mvn package), looked at: ${jar:-<unknown service>}"; exit 1; }
    echo
    echo "running $jar"
    set -a; . "$env_file"; set +a
    case "$service" in
        # security is not a fat jar: its Dockerfile runs the classes with target/lib on the classpath
        security) exec java -cp "$jar:$(dirname "$jar")/lib/*" com.jrobertgardzinski.App ;;
        *)        exec java -jar "$jar" ;;
    esac
fi
