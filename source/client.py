import requests
from textwrap import fill
import json

def display_response(query, response_data):
    """Format and display the response in a user-friendly way"""
    print("\n" + "=" * 60)
    print(f"📩 Your Query: {query}")
    print("=" * 60)
    
    # Format the main response
    response_text = fill(response_data.get('response', 'No response received'), width=60)
    print(f"\n💬 Chatbot Response:\n{response_text}")
    
    # Format actions if any
    if 'actions' in response_data and response_data['actions']:
        print("\n🔧 Actions Taken:")
        for i, action in enumerate(response_data['actions'], 1):
            if isinstance(action, dict):
                # Handle dictionary format
                action_name = action.get('action', 'Unknown action')
                args = action.get('args', {})
                result = action.get('result', 'No result')
                
                print(f"\n{i}. {action_name.upper().replace('_', ' ')}")
                
                if args:
                    print(f"   - Arguments: {json.dumps(args, indent=4)}")
                
                if result and not isinstance(result, str):
                    print(f"   - Result: {json.dumps(result, indent=4)}")
                elif result:
                    print(f"   - Result: {result}")
            elif isinstance(action, str):
                # Handle string format
                print(f"\n{i}. {action}")
            else:
                print(f"\n{i}. [Unknown action format: {type(action)}]")
    
    print("\n" + "=" * 60 + "\n")

def query_chatbot(query):
    url = "http://localhost:8001/chat"
    payload = {"query": query}
    
    try:
        response = requests.post(url, json=payload)
        if response.status_code == 200:
            display_response(query, response.json())
        else:
            print(f"\n❌ Error: Server returned status {response.status_code}")
            print(f"Details: {response.text}\n")
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Error connecting to Chatbot API: {e}\n")

def main():
    print("\n" + "✨" * 25)
    print("🤖 Interactive AI Chatbot Client")
    print("✨" * 25)
    print("\nEnter your questions or commands below.")
    print("Type 'exit' or 'quit' to end the session\n")
    print("-" * 60)
    
    while True:
        try:
            query = input("\nYou: ").strip()
            if query.lower() in ["exit", "quit"]:
                print("\n👋 Thank you for using the AI Chatbot. Goodbye!\n")
                break
            if query:
                query_chatbot(query)
            else:
                print("⚠️ Please enter a valid query")
        except KeyboardInterrupt:
            print("\n👋 Session ended by user. Goodbye!\n")
            break

if __name__ == "__main__":
    main()