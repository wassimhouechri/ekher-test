FROM python:3.11-slim

RUN pip install --no-cache-dir --upgrade pip==24.0 setuptools==70.0.0 wheel==0.43.0
WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY app.py .

# Create non-root user with permissions
RUN useradd -m -u 1001 appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]