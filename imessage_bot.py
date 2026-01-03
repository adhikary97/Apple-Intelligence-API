#!/usr/bin/env python3
"""
iMessage AI Bot - Chat with Apple Intelligence via iMessage
Monitors incoming messages and responds using the local Apple Intelligence API.

Usage:
    python3 imessage_bot.py                           # Respond to everyone (not recommended)
    python3 imessage_bot.py --contact "+14155551234"  # Only respond to this phone number
    python3 imessage_bot.py --contact "friend@icloud.com"  # Only respond to this email
"""

import sqlite3
import subprocess
import requests
import time
import os
import json
import argparse
from pathlib import Path
from datetime import datetime
from collections import defaultdict

# Configuration
API_URL = "http://127.0.0.1:8080/api/v1/chat/completions"
MESSAGES_DB = Path.home() / "Library/Messages/chat.db"
POLL_INTERVAL = 1  # seconds
MODEL = "base"  # or "permissive" for relaxed content filtering

# ============================================================
# 🎯 SET YOUR ALLOWED CONTACTS HERE
# ============================================================
# Only respond to messages from these contacts.
# Use phone numbers (with country code) or Apple ID emails.
# Examples:
#   ALLOWED_CONTACTS = ["+14155551234"]                    # Single contact
#   ALLOWED_CONTACTS = ["+14155551234", "+14155559999"]    # Multiple phones
#   ALLOWED_CONTACTS = ["+14155551234", "friend@icloud.com"]  # Mixed
#   ALLOWED_CONTACTS = []                                  # Respond to everyone (not recommended)
#
ALLOWED_CONTACTS = []  # <-- ADD YOUR CONTACTS HERE!
# ============================================================

# Store conversation history per contact (phone/email)
conversation_history = defaultdict(list)
MAX_HISTORY = 10  # Keep last N messages for context

# Track which messages we've already processed
processed_messages = set()

# Track messages WE sent (to avoid responding to our own messages)
sent_messages = set()
SENT_MESSAGE_EXPIRY = 60  # seconds to remember sent messages
sent_messages_with_time = []  # (timestamp, message_hash)


def get_db_connection():
    """Create a read-only connection to the Messages database."""
    db_path = str(MESSAGES_DB)
    return sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)


def get_recent_messages(since_rowid=0):
    """Fetch recent messages from the iMessage database."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Query to get recent incoming messages
        query = """
        SELECT 
            m.ROWID,
            m.text,
            m.is_from_me,
            m.date,
            h.id as sender,
            c.chat_identifier
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        LEFT JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE m.ROWID > ?
            AND m.text IS NOT NULL
            AND m.text != ''
            AND m.is_from_me = 0
        ORDER BY m.ROWID ASC
        LIMIT 50
        """
        
        cursor.execute(query, (since_rowid,))
        messages = cursor.fetchall()
        conn.close()
        
        return [
            {
                "rowid": row[0],
                "text": row[1],
                "is_from_me": row[2],
                "date": row[3],
                "sender": row[4] or row[5],
                "chat_id": row[5]
            }
            for row in messages
        ]
    except Exception as e:
        print(f"❌ Error reading messages: {e}")
        return []


def get_latest_rowid():
    """Get the most recent message ROWID to start from."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT MAX(ROWID) FROM message")
        result = cursor.fetchone()
        conn.close()
        return result[0] or 0
    except Exception as e:
        print(f"❌ Error getting latest rowid: {e}")
        return 0


def clean_old_sent_messages():
    """Remove old entries from sent_messages tracking."""
    global sent_messages_with_time
    current_time = time.time()
    # Keep only messages from the last SENT_MESSAGE_EXPIRY seconds
    sent_messages_with_time = [
        (ts, msg_hash) for ts, msg_hash in sent_messages_with_time
        if current_time - ts < SENT_MESSAGE_EXPIRY
    ]
    # Update the set
    sent_messages.clear()
    sent_messages.update(msg_hash for _, msg_hash in sent_messages_with_time)


def is_our_sent_message(message: str) -> bool:
    """Check if this message was recently sent by us (to avoid loops)."""
    clean_old_sent_messages()
    msg_hash = hash(message.strip().lower())
    return msg_hash in sent_messages


def track_sent_message(message: str):
    """Track a message we're sending to avoid responding to it later."""
    msg_hash = hash(message.strip().lower())
    sent_messages.add(msg_hash)
    sent_messages_with_time.append((time.time(), msg_hash))


def send_imessage(recipient: str, message: str):
    """Send an iMessage using AppleScript."""
    # Track this message so we don't respond to it if it comes back
    track_sent_message(message)
    
    # Escape special characters for AppleScript
    escaped_message = message.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    
    applescript = f'''
    tell application "Messages"
        set targetService to 1st account whose service type = iMessage
        set targetBuddy to participant "{recipient}" of targetService
        send "{escaped_message}" to targetBuddy
    end tell
    '''
    
    try:
        subprocess.run(
            ['osascript', '-e', applescript],
            capture_output=True,
            text=True,
            timeout=30
        )
        return True
    except subprocess.TimeoutExpired:
        print(f"❌ Timeout sending message to {recipient}")
        return False
    except Exception as e:
        print(f"❌ Error sending message: {e}")
        return False


def get_ai_response(sender: str, message: str) -> str:
    """Get a response from the Apple Intelligence API with conversation context."""
    
    # Add user message to history
    conversation_history[sender].append({
        "role": "user",
        "content": message
    })
    
    # Keep only recent history
    if len(conversation_history[sender]) > MAX_HISTORY * 2:
        conversation_history[sender] = conversation_history[sender][-MAX_HISTORY * 2:]
    
    # Build messages array with context
    messages = [
        {
            "role": "system",
            "content": "You are a helpful AI assistant responding via iMessage. Keep responses concise and conversational. Use emojis sparingly but appropriately."
        }
    ] + conversation_history[sender]
    
    try:
        response = requests.post(
            API_URL,
            json={
                "model": MODEL,
                "messages": messages
            },
            timeout=60
        )
        
        if response.status_code == 200:
            data = response.json()
            ai_response = data["choices"][0]["message"]["content"]
            
            # Add AI response to history
            conversation_history[sender].append({
                "role": "assistant",
                "content": ai_response
            })
            
            return ai_response
        else:
            print(f"❌ API error: {response.status_code} - {response.text}")
            return "Sorry, I couldn't process that. Please try again."
            
    except requests.exceptions.ConnectionError:
        return "⚠️ AI server is not running. Please start the Apple Intelligence API."
    except requests.exceptions.Timeout:
        return "⏱️ Response took too long. Please try again."
    except Exception as e:
        print(f"❌ Error calling API: {e}")
        return "Something went wrong. Please try again."


def check_permissions():
    """Check if we have access to the Messages database."""
    if not MESSAGES_DB.exists():
        print("❌ Messages database not found!")
        print(f"   Expected at: {MESSAGES_DB}")
        return False
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM message")
        conn.close()
        return True
    except sqlite3.OperationalError as e:
        if "unable to open database" in str(e).lower():
            print("❌ Cannot access Messages database!")
            print("   Grant Full Disk Access to Terminal/Python:")
            print("   → System Settings → Privacy & Security → Full Disk Access")
            print("   → Add Terminal.app (or your terminal of choice)")
        return False


def print_banner():
    """Print startup banner."""
    print("""
╔═══════════════════════════════════════════════════════════╗
║           🤖 iMessage AI Bot (Apple Intelligence)          ║
╠═══════════════════════════════════════════════════════════╣
║  Monitoring for incoming messages...                       ║
║  Send a message to this Mac's iMessage to chat with AI    ║
║                                                            ║
║  Commands:  /clear - Reset conversation                    ║
║             /help  - Show available commands               ║
║                                                            ║
║  Press Ctrl+C to stop                                      ║
╚═══════════════════════════════════════════════════════════╝
    """)
    if ALLOWED_CONTACTS:
        print(f"🎯 Only responding to: {', '.join(ALLOWED_CONTACTS)}")
    else:
        print("⚠️  Warning: Responding to ALL contacts!")
        print("   Set ALLOWED_CONTACTS in the script to limit responses.")


def main():
    global ALLOWED_CONTACTS, MODEL
    
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description="iMessage AI Bot - Chat with Apple Intelligence via iMessage"
    )
    parser.add_argument(
        "--contact", "-c",
        type=str,
        action="append",
        dest="contacts",
        help="Contact to allow (can be used multiple times). Example: -c +14155551234 -c friend@icloud.com"
    )
    parser.add_argument(
        "--model", "-m",
        type=str,
        default="base",
        choices=["base", "permissive"],
        help="AI model to use (default: base)"
    )
    args = parser.parse_args()
    
    # Override config with command-line args
    if args.contacts:
        ALLOWED_CONTACTS = args.contacts
    if args.model:
        MODEL = args.model
    
    print_banner()
    
    # Check permissions
    if not check_permissions():
        return
    
    # Check if API is running
    try:
        response = requests.get(f"{API_URL.replace('/chat/completions', '/models')}", timeout=5)
        print(f"✅ Connected to Apple Intelligence API")
        print(f"   Models available: {[m['id'] for m in response.json().get('data', [])]}")
    except:
        print("⚠️  Warning: Cannot reach Apple Intelligence API at", API_URL)
        print("   Make sure the server is running with: swift run AppleIntelligenceApi serve")
        print()
    
    # Start from the latest message (don't process old ones)
    last_rowid = get_latest_rowid()
    print(f"📍 Starting from message ID: {last_rowid}")
    print(f"🔄 Polling every {POLL_INTERVAL} second(s)...")
    print()
    
    try:
        while True:
            # Get new messages
            new_messages = get_recent_messages(last_rowid)
            
            for msg in new_messages:
                rowid = msg["rowid"]
                
                # Skip if already processed
                if rowid in processed_messages:
                    continue
                
                processed_messages.add(rowid)
                last_rowid = max(last_rowid, rowid)
                
                sender = msg["sender"]
                text = msg["text"]
                
                # Skip messages we sent ourselves (prevents infinite loop when messaging self)
                if is_our_sent_message(text):
                    print(f"🔄 [{datetime.now().strftime('%H:%M:%S')}] Skipped our own message (loop prevention)")
                    continue
                
                # Filter by allowed contacts
                if ALLOWED_CONTACTS:  # Only filter if list is not empty
                    sender_normalized = sender.strip().lower() if sender else ""
                    sender_no_plus = sender_normalized.lstrip('+')
                    
                    # Check if sender matches any allowed contact
                    is_allowed = False
                    for allowed in ALLOWED_CONTACTS:
                        allowed_normalized = allowed.strip().lower()
                        allowed_no_plus = allowed_normalized.lstrip('+')
                        
                        if sender_normalized == allowed_normalized or sender_no_plus == allowed_no_plus:
                            is_allowed = True
                            break
                    
                    if not is_allowed:
                        print(f"⏭️  [{datetime.now().strftime('%H:%M:%S')}] Ignored message from {sender} (not in allowed list)")
                        continue
                
                print(f"📨 [{datetime.now().strftime('%H:%M:%S')}] From {sender}:")
                print(f"   \"{text}\"")
                
                # Handle commands
                if text.strip().lower() == "/clear":
                    conversation_history[sender].clear()
                    print(f"🧹 Cleared conversation history for {sender}")
                    send_imessage(sender, "✨ Conversation cleared! Starting fresh.")
                    continue
                
                if text.strip().lower() == "/help":
                    help_text = "🤖 iMessage AI Bot Commands:\n\n/clear - Reset conversation history\n/help - Show this message"
                    send_imessage(sender, help_text)
                    continue
                
                # Get AI response
                print(f"🤔 Thinking...")
                ai_response = get_ai_response(sender, text)
                
                print(f"🤖 Response:")
                print(f"   \"{ai_response[:100]}{'...' if len(ai_response) > 100 else ''}\"")
                
                # Send reply
                if send_imessage(sender, ai_response):
                    print(f"✅ Sent reply to {sender}")
                else:
                    print(f"❌ Failed to send reply to {sender}")
                
                print()
            
            time.sleep(POLL_INTERVAL)
            
    except KeyboardInterrupt:
        print("\n\n👋 Shutting down iMessage AI Bot...")
        print("   Goodbye!")


if __name__ == "__main__":
    main()

