from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import mysql.connector

# Initialize FastAPI app
app = FastAPI(title="Student CRUD API", description="API for managing student records")

# Add CORS middleware to allow requests from chatbot API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8001"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# MySQL database connection
db_config = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "ai_chat_bot_db",
}

# Database connection helper
def get_db_connection():
    return mysql.connector.connect(**db_config)

# Create student
@app.post("/students")
async def create_student(student: dict):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            "INSERT INTO students (name, age) VALUES (%s, %s)",
            (student["name"], student["age"]),
        )
        conn.commit()
        cursor.execute("SELECT * FROM students WHERE id = LAST_INSERT_ID()")
        result = cursor.fetchone()
        return {"id": result[0], "name": result[1], "age": result[2]}
    finally:
        cursor.close()
        conn.close()

# Get all students
@app.get("/students")
async def get_students():
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT * FROM students")
        students = [{"id": row[0], "name": row[1], "age": row[2]} for row in cursor.fetchall()]
        return students
    finally:
        cursor.close()
        conn.close()

# Get single student by ID
@app.get("/students/{student_id}")
async def get_student(student_id: int):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT * FROM students WHERE id = %s", (student_id,))
        result = cursor.fetchone()
        if not result:
            raise HTTPException(status_code=404, detail="Student not found")
        return {"id": result[0], "name": result[1], "age": result[2]}
    finally:
        cursor.close()
        conn.close()

# Update student
@app.put("/students/{student_id}")
async def update_student(student_id: int, student: dict):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            "UPDATE students SET name = %s, age = %s WHERE id = %s",
            (student["name"], student["age"], student_id),
        )
        conn.commit()
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Student not found")
        cursor.execute("SELECT * FROM students WHERE id = %s", (student_id,))
        result = cursor.fetchone()
        return {"id": result[0], "name": result[1], "age": result[2]}
    finally:
        cursor.close()
        conn.close()

# Delete student
@app.delete("/students/{student_id}")
async def delete_student(student_id: int):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM students WHERE id = %s", (student_id,))
        conn.commit()
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Student not found")
        return {"message": "Student deleted successfully"}
    finally:
        cursor.close()
        conn.close()
