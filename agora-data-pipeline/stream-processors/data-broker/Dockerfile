FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY broker.py .
COPY transformations/ transformations/

EXPOSE 8000

ENV PYTHONUNBUFFERED=1 \
    METRICS_PORT=8000

CMD ["python", "broker.py"]
