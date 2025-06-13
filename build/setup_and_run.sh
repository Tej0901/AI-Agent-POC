#!/bin/bash
set -Eeuo pipefail # -E: ERR traps inherited, -u: unset vars error, -o pipefail: errors in pipelines

# ---------------- Colors and Symbols ----------------
BOLD=$(tput bold)
RESET=$(tput sgr0)
TICK="✅"
CROSS="❌"
INFO="🔷"

# ---------------- Project Setup ----------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# Fix for unbound variable: Append to PYTHONPATH if it's already set, otherwise start with PROJECT_ROOT
export PYTHONPATH="$PROJECT_ROOT:${PYTHONPATH:-}"

# Server ports globally
SERVER_CRUD_PORT=8000
SERVER_CHATBOT_PORT=8001

# --- Cleanup Function ---
# This function will be called upon script exit or interruption
cleanup() {
    if [ -z "${CLEANUP_DONE+x}" ]; then
        echo -e "\n🛑 ${BOLD}Stopping servers and cleaning up...${RESET}"
        export CLEANUP_DONE=true

        local STOPPED_COUNT=0
        local FAILED_COUNT=0

        # Check for lsof availability
        if ! command -v lsof &> /dev/null; then
            echo -e "$CROSS 'lsof' command not found. Cannot reliably stop servers by port."
            echo -e "  Please install 'lsof' (e.g., 'sudo apt install lsof' on Ubuntu, 'brew install lsof' on macOS)."
        fi

        # Helper function to stop a process by port
        stop_process_by_port() {
            local port=$1
            local name=$2
            local pid=""

            if command -v lsof &> /dev/null; then
                echo -n "Searching for $name on port $port... "
                pid=$(lsof -ti:"$port" 2>/dev/null)

                if [ -z "$pid" ]; then
                    echo -e "$TICK $name not found running on port $port or already stopped."
                    return 0
                fi

                echo -n "Found $name (PID: $pid) on port $port. Attempting to stop... "
                # Attempt graceful shutdown first, then forceful
                if kill -TERM "$pid" 2>/dev/null; then
                    sleep 1
                    if ! kill -0 "$pid" 2>/dev/null; then # Check if it's really gone
                        echo -e "$TICK Stopped."
                        STOPPED_COUNT=$((STOPPED_COUNT + 1))
                    else
                        echo -n "Still running, forcing stop... "
                        if kill -9 "$pid" 2>/dev/null; then
                            echo -e "$TICK Force stopped."
                            STOPPED_COUNT=$((STOPPED_COUNT + 1))
                        else
                            echo -e "$CROSS Failed to force stop."
                            FAILED_COUNT=$((FAILED_COUNT + 1))
                        fi
                    fi
                else
                    echo -e "$CROSS Failed to send TERM signal."
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                fi
            else
                echo -e "  (Skipping $name cleanup as 'lsof' is not available)"
            fi
        }

        # Stop the FastAPI servers by their known ports
        stop_process_by_port "$SERVER_CRUD_PORT" "CRUD Server"
        stop_process_by_port "$SERVER_CHATBOT_PORT" "Chatbot Server"

        # Provide a summary of the cleanup
        if [ "$STOPPED_COUNT" -gt 0 ] && [ "$FAILED_COUNT" -eq 0 ]; then
            echo -e "$TICK All active servers stopped successfully."
        elif [ "$STOPPED_COUNT" -gt 0 ] && [ "$FAILED_COUNT" -gt 0 ]; then
            echo -e "⚠️ Some servers stopped, but $FAILED_COUNT failed or were not found."
        elif [ "$STOPPED_COUNT" -eq 0 ] && [ "$FAILED_COUNT" -eq 0 ] && command -v lsof &> /dev/null; then
            echo -e "$TICK No active servers found to stop or all were already stopped (checked by port)."
        else # lsof not found or other failures
            echo -e "$CROSS Failed to stop any active servers, or could not check status without 'lsof'."
        fi

        # Deactivate virtual environment
        if type deactivate &> /dev/null; then
            deactivate
            echo -e "$TICK Virtual environment deactivated."
        else
            echo -e "$CROSS Could not deactivate virtual environment (might not be active or 'deactivate' not in path)."
        fi

        # Remove virtual environment directory
        if [ -d "$PROJECT_ROOT/venv" ]; then
            echo -n "  - Removing virtual environment... "
            rm -rf "$PROJECT_ROOT/venv"
            echo -e "$TICK Removed virtual environment folder."
        else
            echo -e "$CROSS Virtual environment directory not found."
        fi
    fi
    exit 0
}

# --- Trap Signals ---
# Calls the cleanup function when a SIGINT (Ctrl+C), SIGTERM, or EXIT signal is received.
trap cleanup SIGINT SIGTERM EXIT

# ---------------- Fix SSL Certificates ----------------
fix_ssl() {
    echo -e "\n$INFO ${BOLD}Fixing SSL certificates...${RESET}"
    PYTHON_VERSION=$("$PYTHON" -V 2>&1 | cut -d' ' -f2)
    CERT_CMD="/Applications/Python ${PYTHON_VERSION}/Install Certificates.command"
    if [ -f "$CERT_CMD" ]; then
        echo "  - Running macOS Install Certificates.command..."
        "$CERT_CMD"
    elif command -v update-ca-certificates &> /dev/null; then
        echo "  - Running update-ca-certificates..."
        sudo update-ca-certificates --fresh
    fi
}

# ---------------- Python & Virtualenv ----------------
echo -e "\n$INFO ${BOLD}Checking Python3 and pip3...${RESET}"

PYTHON=$(command -v python3)
PIP=$(command -v pip3)

if [[ -z "$PYTHON" || -z "$PIP" ]]; then
  echo -e "$CROSS Python3 and pip3 are required. Please install them. Exiting."
  exit 1
fi

echo "$TICK Found Python: $($PYTHON --version)"
echo "$TICK Found pip: $($PIP --version)"

fix_ssl

echo -e "\n$INFO ${BOLD}Creating virtual environment...${RESET}"
"$PYTHON" -m venv "$PROJECT_ROOT/venv"
source "$PROJECT_ROOT/venv/bin/activate"

export SSL_CERT_FILE=$(python3 -c "import ssl; print(ssl.get_default_verify_paths().openssl_cafile)")

# ---------------- Install Dependencies ----------------
echo -e "\n$INFO ${BOLD}Installing dependencies (this may take a moment)...${RESET}"

echo "$TICK Installing core libraries..."
pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org \
    --upgrade pip > /dev/null

pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org \
    fastapi uvicorn pyyaml pydantic requests mysql-connector-python python-dotenv urllib3==1.26.18 > /dev/null 2>&1

echo "$TICK Installing Google ADK..."
pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org \
    google-adk > /dev/null

echo -e "\n$TICK ${BOLD}All dependencies installed successfully.${RESET}"

# ---------------- API Key Input ----------------
echo -e "\n🔐 ${BOLD}Enter your Google Gemini API key:${RESET}"
read -s -p "Gemini API Key: " GEMINI_KEY
echo
export GOOGLE_API_KEY="$GEMINI_KEY"

# ---------------- Database Setup ----------------
echo -e "\n🛠️  Setting up MySQL database..."
DB_USER="root"
DB_NAME="ai_chat_bot_db"
DEFAULT_SQL_FILE="product_package/data_dictionary/db.sql"
SQL_FILE="${SQL_FILE_PATH:-${1:-$DEFAULT_SQL_FILE}}"

echo -e "\n🔑 ${BOLD}Enter your MySQL root password (if any, otherwise enter):${RESET}"
read -s -p "MySQL Password: " MYSQL_ROOT_PASSWORD
echo
export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"

if ! command -v mysql &> /dev/null; then
    echo -e "$CROSS MySQL client is not installed. Please install MySQL client to proceed."
    exit 1
fi

if [[ ! "$SQL_FILE" = /* ]]; then
    SQL_FILE_PATH="$PROJECT_ROOT/$SQL_FILE"
else
    SQL_FILE_PATH="$SQL_FILE"
fi

if [ ! -f "$SQL_FILE_PATH" ]; then
    echo -e "$CROSS SQL file not found at: $SQL_FILE_PATH"
    echo -e "Use: export SQL_FILE_PATH=/full/path/to/db.sql or ./$(basename "$0") /full/path/to/db.sql"
    exit 1
fi

echo -n "  - Creating database '$DB_NAME' if it doesn't exist... "
mysql -u"$DB_USER" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "$CROSS Could not create database '$DB_NAME'."
    echo "  Please check your MySQL server status and user credentials (e.g., if 'root' requires a password)."
    exit 1
else
    echo -e "$TICK Done."
fi

echo -n "  - Loading SQL file '$SQL_FILE_PATH' into '$DB_NAME'... "
mysql -u"$DB_USER" "$DB_NAME" < "$SQL_FILE_PATH" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "$CROSS Could not load SQL file '$SQL_FILE_PATH'."
    echo "  Please ensure the SQL file is valid and MySQL user has sufficient permissions."
    exit 1
else
    echo -e "$TICK Done."
fi

echo -e "$TICK Database '$DB_NAME' is ready."
unset MYSQL_PWD

# ---------------- Start FastAPI Servers ----------------
echo -e "\n🚀 ${BOLD}Starting FastAPI servers in background...${RESET}"

# Start servers using their defined ports
"$PROJECT_ROOT/venv/bin/uvicorn" source.student_crud:app \
    --host 0.0.0.0 --port "$SERVER_CRUD_PORT" --app-dir "$PROJECT_ROOT" > "$PROJECT_ROOT/server_crud.log" 2>&1 &
echo "$TICK student_crud.py running at http://localhost:$SERVER_CRUD_PORT (logs in server_crud.log)"

"$PROJECT_ROOT/venv/bin/uvicorn" source.openapi_toolset:app \
    --host 0.0.0.0 --port "$SERVER_CHATBOT_PORT" --app-dir "$PROJECT_ROOT" > "$PROJECT_ROOT/server_chatbot.log" 2>&1 &
echo "$TICK openapi_toolset.py running at http://localhost:$SERVER_CHATBOT_PORT (logs in server_chatbot.log)"

echo -e "Waiting for servers to fully start (3 seconds)..."
sleep 3

# Add a quick check to see if servers are *actually* running on ports
if ! command -v lsof &> /dev/null; then
    echo -e "$CROSS WARNING: 'lsof' command not found. Cannot verify if servers started on ports. Please install 'lsof'."
elif [ -z "$(lsof -ti:"$SERVER_CRUD_PORT" 2>/dev/null)" ] || [ -z "$(lsof -ti:"$SERVER_CHATBOT_PORT" 2>/dev/null)" ]; then
    echo -e "\n$CROSS ERROR: One or more FastAPI servers failed to start on its port ($SERVER_CRUD_PORT or $SERVER_CHATBOT_PORT). Check logs ($PROJECT_ROOT/server_crud.log, $PROJECT_ROOT/server_chatbot.log)."
    cleanup # Call cleanup immediately if servers didn't start
fi

# ---------------- Run Interactive Client in Same Terminal ----------------
echo -e "\n🧠 ${BOLD}Starting interactive chatbot client in this terminal...${RESET}"

CLIENT_FILE="source/client.py"
CLIENT_FILE_PATH="$PROJECT_ROOT/$CLIENT_FILE"

if [ ! -f "$CLIENT_FILE_PATH" ]; then
    echo -e "❌ Client file not found at: $CLIENT_FILE_PATH"
    cleanup
    exit 1
fi

cd "$PROJECT_ROOT"
"$PROJECT_ROOT/venv/bin/python" "$CLIENT_FILE"
