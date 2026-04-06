# DevSecOps Pipeline — Setup Complet

## Structure du projet

```
devsecops-project/
├── app/
│   ├── app.py              ← Flask app (auth, rate limit, security headers)
│   ├── requirements.txt    ← Dépendances Python épinglées
│   └── Dockerfile          ← Image sécurisée (non-root, hadolint-clean)
├── k8s/
│   ├── deployment.yaml     ← Déploiement K8s (securityContext complet)
│   ├── service.yaml        ← Service LoadBalancer
│   ├── networkpolicy.yaml  ← Isolation réseau entre pods
│   └── secret.yaml         ← Template Secret K8s (ne pas committer de vraies valeurs)
├── .github/
│   └── workflows/
│       └── devsecops.yml   ← Pipeline CI/CD + sécurité complet
├── .zap/
│   └── rules.tsv           ← Suppressions faux positifs ZAP
├── .gitleaks.toml          ← Config Gitleaks
├── .bandit                 ← Config Bandit
├── .semgrep.yml            ← Règles Semgrep custom
├── .trivyignore            ← CVEs acceptés (documentés)
└── README.md
```

---

## Ce que couvre le pipeline

| Catégorie | Outil | Quand |
|-----------|-------|-------|
| Secrets dans le code | Gitleaks | Job 1 |
| SAST Python | Bandit | Job 1 |
| SAST multi-langage + OWASP | Semgrep | Job 1 |
| CVE dans les dépendances | Safety CLI | Job 1 |
| Licence open source | pip-licenses | Job 1 |
| Lint Dockerfile | Hadolint | Job 1 |
| Scan IaC K8s | Checkov | Job 2 |
| CVE image container | Trivy | Job 2 |
| Signature image | Cosign (keyless) | Job 2 |
| Attaques HTTP (DAST) | OWASP ZAP | Job 3 |
| Déploiement sécurisé | kubectl | Job 4 |

---

## Prérequis

| Outil | Usage | Lien |
|-------|-------|------|
| Git | Source control | https://git-scm.com |
| Docker | Build & run containers | https://docs.docker.com/get-docker |
| kubectl | Parler à Kubernetes | https://kubernetes.io/docs/tasks/tools |
| minikube | Cluster K8s local | https://minikube.sigs.k8s.io/docs/start |
| Cosign | Signer les images | https://docs.sigstore.dev/cosign/installation |
| GitHub account | Héberger le code | https://github.com |

---

## Étape 1 — Créer le dépôt GitHub

```bash
git init
git add .
git commit -m "Initial commit: DevSecOps project"

# Sur GitHub : créer un dépôt nommé "devsecops-project"
git remote add origin https://github.com/YOUR_USERNAME/devsecops-project.git
git push -u origin main
```

---

## Étape 2 — Configurer les GitHub Secrets

`GitHub repo → Settings → Secrets and variables → Actions → New repository secret`

### KUBECONFIG

```bash
cat ~/.kube/config | base64 | tr -d '\n'
# Coller le résultat comme valeur du secret KUBECONFIG
```

> `GITHUB_TOKEN` est automatique — GitHub le fournit.

---

## Étape 3 — Créer le Secret K8s pour l'API Key

```bash
# Générer une clé aléatoire et créer le secret K8s
kubectl create secret generic flask-app-secret \
  --from-literal=api-key="$(openssl rand -hex 32)"

# NE PAS committer de vraies valeurs dans secret.yaml
```

---

## Étape 4 — Démarrer minikube

```bash
minikube start --driver=docker
kubectl get nodes

# Activer le tunnel pour les services LoadBalancer
minikube tunnel
```

---

## Étape 5 — Autoriser K8s à puller l'image depuis ghcr.io

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_GITHUB_TOKEN \
  --docker-email=YOUR_EMAIL
```

---

## Étape 6 — Pousser le code pour déclencher le pipeline

```bash
git add .
git commit -m "Trigger pipeline"
git push origin main
```

Puis : `GitHub repo → Actions` pour suivre l'exécution.

---

## Tester les outils en local

```bash
# Installer les outils
pip install bandit safety semgrep pip-licenses

# Bandit — SAST Python
bandit -r app/ --severity-level medium

# Safety — CVE dans les dépendances
safety check -r app/requirements.txt

# Semgrep — SAST multi-langage
semgrep scan --config "p/python" --config "p/owasp-top-ten" app/

# Hadolint — Dockerfile lint
docker run --rm -i hadolint/hadolint < app/Dockerfile

# Checkov — IaC scan K8s
pip install checkov
checkov -d k8s/ --framework kubernetes

# Trivy — scan image container
docker build -t devsecops-project:local ./app
trivy image devsecops-project:local --severity HIGH,CRITICAL

# Gitleaks — secrets dans git history
gitleaks detect --source . --verbose

# pip-licenses — licences open source
pip install pip-licenses
pip-licenses --format=table
```

---

## Sécurité de l'application

### Headers HTTP de sécurité (automatiques)

Chaque réponse de l'API inclut :

| Header | Valeur |
|--------|--------|
| `Content-Security-Policy` | `default-src 'none'; frame-ancestors 'none'` |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `no-referrer` |

### Authentification

L'endpoint `/api/data` requiert un header `X-API-Key` :

```bash
curl -H "X-API-Key: votre-clé" http://localhost:5000/api/data
```

Configurer la clé via variable d'environnement :

```bash
export API_KEY="votre-clé-secrète"
python app.py
```

### Rate Limiting

60 requêtes maximum par minute par IP (configurable via `RATE_LIMIT` et `RATE_WINDOW`).

---

## Comportement du pipeline en cas d'échec

| Situation | Comportement |
|-----------|-------------|
| Secret trouvé (Gitleaks) | Job 1 échoue → Jobs 2, 3, 4 annulés |
| Code dangereux (Bandit/Semgrep) | Job 1 échoue → Jobs 2, 3, 4 annulés |
| CVE critique (Safety) | Job 1 échoue → Jobs 2, 3, 4 annulés |
| Dockerfile non conforme (Hadolint) | Job 1 échoue → Jobs 2, 3, 4 annulés |
| Mauvaise pratique IaC (Checkov) | Job 2 échoue → Jobs 3, 4 annulés |
| CVE critique image (Trivy) | Job 2 échoue → Jobs 3, 4 annulés |
| Vulnérabilité HTTP (ZAP) | Job 3 échoue → Job 4 annulé |
| Signature invalide (Cosign) | Job 4 échoue avant le déploiement |
| Tous les jobs passent | Job 4 déploie sur Kubernetes |

---

## Dépannage

### Checkov bloque le build
Un manifest K8s ne respecte pas une règle de sécurité. Consulter le rapport `checkov-report` dans les artifacts GitHub Actions. Corriger la configuration ou ajouter une suppression documentée dans le manifest :
```yaml
metadata:
  annotations:
    checkov.io/skip1: "CKV_K8S_XXX=Justification documentée"
```

### Cosign échoue au déploiement
L'image n'a pas été signée (job 2 non exécuté sur main). Vérifier que `id-token: write` est bien dans les permissions du job build-scan.

### Trivy bloque le build
Un CVE HIGH/CRITICAL a été trouvé. Solutions :
1. Mettre à jour l'image de base : `FROM python:3.11-slim` → vérifier les nouvelles versions
2. Ajouter au `.trivyignore` avec justification et date d'expiration

### Safety CLI échoue
Une dépendance obsolète a été trouvée. Mettre à jour `requirements.txt` avec la version corrigée recommandée par Safety.

### ZAP scan échoue
Une vraie vulnérabilité a été détectée. Consulter le rapport `zap-report` dans les artifacts GitHub Actions. Si c'est un faux positif, ajouter l'alerte dans `.zap/rules.tsv` :
```
10015  IGNORE  (raison)
```

### KUBECONFIG ne fonctionne pas
Encoder en base64 avant de stocker :
```bash
cat ~/.kube/config | base64 | tr -d '\n'
```

### minikube : image introuvable
Charger l'image locale dans minikube :
```bash
minikube image load devsecops-project:local
```
# devsecops-project2
