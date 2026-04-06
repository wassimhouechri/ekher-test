FROM python:3.11-slim

# Éviter les warnings pip et optimiser les couches
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Installer gunicorn (pour la production) et pip
RUN pip install --no-cache-dir --upgrade pip==24.0 setuptools==70.0.0 wheel==0.43.0 gunicorn==21.2.0

WORKDIR /app

# Copier requirements (optimisation du cache Docker)
COPY requirements.txt .

# Installer les dépendances (sans outils de sécurité)
RUN pip install --no-cache-dir -r requirements.txt

# Copier l'application
COPY app.py .

# Créer un utilisateur non-root avec les bonnes permissions
RUN useradd -m -u 1001 appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 5000

# Utiliser gunicorn en production (meilleures performances)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "--threads", "2", "app:app"]