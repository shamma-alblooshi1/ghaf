from setuptools import find_packages, setup

setup(
    name="agents",
    version="0.1.0",
    description="Agent-to-Agent (A2A) communication system with orchestration capabilities",
    author="Your Name",
    author_email="your.email@example.com",
    packages=find_packages(),
    python_requires=">=3.11",
    install_requires=[
        "asyncclick>=8.1.8",
        "click>=8.1.8",
        "google-adk>=0.2.0",
        "httpx>=0.28.1",
        "httpx-sse>=0.4.0",
        "langchain-google-genai>=2.1.4",
        "langchain-mcp-adapters>=0.0.11",
        "langgraph>=0.4.3",
        "mcp>=1.8.0",
        "pydantic>=2.11.3",
        "python-dotenv>=1.1.0",
        "starlette>=0.46.2",
        "uvicorn>=0.34.2",
        "psutil>=7.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-asyncio>=0.21.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.7.0",
        ],
    },
    entry_points={
        "console_scripts": [  # to be changed
            "a2a-cli=app.cmd.cmd:cli",
            "host-agent=agents.host_agent.entry:main",
            "syscall-monitor=agents.syscall_monitor_agent.__main__:main",
        ],
    },
)
