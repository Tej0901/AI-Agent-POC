import uuid
import yaml
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from google.adk.agents import LlmAgent
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types
from google.adk.tools.openapi_tool.openapi_spec_parser.openapi_toolset import OpenAPIToolset

# FastAPI app setup
app = FastAPI(title="Student Chatbot API", description="Chatbot for student management")

# Allow CORS for client requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Models for request and response
class ChatRequest(BaseModel):
    query: str

class ChatResponse(BaseModel):
    response: str
    actions: list[str]

# Global Variables
APP_NAME = "student_crud_app"
USER_ID = "user_1"
SESSION_ID = f"session_student_{uuid.uuid4()}"
AGENT_NAME = "student_manager_agent"
AI_MODEL = "gemini-2.0-flash"
runner: Runner = None
generated_tools_list: list = []


# Load OpenAPI spec
try:
    # Resolving paths
    OPENAPI_SPEC_PATH = "product_package/spec/openapi_student_crud.yaml"
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))  # source/
    PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)  # <root>/
    OPENAPI_FILE_PATH = os.path.join(PROJECT_ROOT, OPENAPI_SPEC_PATH)

    if not os.path.isfile(OPENAPI_FILE_PATH):
        raise FileNotFoundError(f"OpenAPI spec file not found at: {OPENAPI_FILE_PATH}")
    with open(OPENAPI_FILE_PATH, "r") as f:
        openapi_spec_string = f.read()
    yaml.safe_load(openapi_spec_string)
    
    print(f"Loaded OpenAPI spec from {OPENAPI_FILE_PATH}")

except FileNotFoundError as e:
    print(f"Error: {e}")
    print("Ensure product_package/spec/openapi_student_crud.yaml is in the repository.")
    exit(1)
except yaml.YAMLError as e:
    print(f"Error: Invalid YAML in OpenAPI spec: {e}")
    exit(1)
except Exception as e:
    print(f"Unexpected error loading OpenAPI spec: {e}")
    exit(1)


@app.on_event("startup")
async def startup_event():

    global generated_tools_list, runner, SESSION_ID

    print("Running startup event...")
    try:
        tool_set = OpenAPIToolset(spec_str=openapi_spec_string, spec_str_type="yaml")
        generated_tools_list = await tool_set.get_tools()
        print(f"Generated {len(generated_tools_list)} tools: {[t.name for t in generated_tools_list]}")

        # Define AI agent
        student_agent = LlmAgent(
            name=AGENT_NAME,
            model=AI_MODEL,
            tools=generated_tools_list,
            instruction=f"""You are a **Student Management Assistant**. Your primary goal is to efficiently manage student records.
                
                **Core Principles:**
                1.  **Utilize Tools First:** Whenever possible, use the available tools to perform actions (create, update, get, delete, list).
                2.  **Confirm Details:** For all **create** and **update** operations, explicitly confirm the details with the user before proceeding.
                3.  **Provide Counts:** For **list** operations, always mention the total number of records found.
                4.  **Specify IDs:** For **get** and **delete** operations, clearly state the ID of the student being acted upon.
                5.  **Proactive Filtering & Analysis:** If a user requests a specific subset of data (e.g., "students older than 18," "students with GPA above 3.5"), first use the **list** tool to retrieve all relevant data. Then, process and filter this data internally to provide the precise information requested. You are capable of performing logical operations (e.g., greater than, less than, equals, contains) on numerical and string fields to fulfill these requests.
                6.  **Summarize & Compare:** If a user asks for summaries (e.g., "average GPA," "number of students in each major") or comparisons (e.g., "compare GPAs of two students"), retrieve the necessary data using the **list** or **get** tools, then perform the calculations and present the insights.
                7.  **Handle Ambiguity & Clarify:** If a request is ambiguous or requires more information, ask clarifying questions to ensure you understand the user's intent.
                8.  **Provide Helpful Context:** Beyond direct answers, offer additional relevant information or next steps that might be useful to the user.
                
                Available Tools: {', '.join([t.name for t in generated_tools_list])}.""",
            description="Manages student records via API tools."
        )

        # Session and runner setup
        session_service = InMemorySessionService()
        runner = Runner(
            agent=student_agent, app_name=APP_NAME, session_service=session_service
        )
        await session_service.create_session(app_name=APP_NAME, user_id=USER_ID, session_id=SESSION_ID)

        print("Agent and tools initialized successfully.")

    except Exception as e:
        print(f"Error during startup initialization: {e}")


# Agent interaction function
async def call_student_agent_async(query: str) -> tuple[str, list[str]]:
    content = types.Content(role="user", parts=[types.Part(text=query)])
    actions = []
    response_text = "No response from agent."
    
    try:
        async for event in runner.run_async(user_id=USER_ID, session_id=SESSION_ID, new_message=content):
            if event.get_function_calls():
                call = event.get_function_calls()[0]
                actions.append(f"Called '{call.name}' with args {call.args}")
            elif event.get_function_responses():
                response = event.get_function_responses()[0]
                actions.append(f"Got response for '{response.name}'")
            elif event.is_final_response() and event.content and event.content.parts:
                response_text = event.content.parts[0].text.strip()
        return response_text, actions
    except Exception as e:
        return f"Error: {str(e)}", actions

# Chat Bot endpoint
@app.post("/chat", response_model=ChatResponse)
async def chat_with_student_agent(request: ChatRequest):
    response_text, actions = await call_student_agent_async(request.query)
    return ChatResponse(response=response_text, actions=actions)

# Health check endpoint
@app.get("/health")
async def health_check():
    return {"status": "healthy"}