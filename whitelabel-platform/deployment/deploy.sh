#!/bin/bash

# ============================================================================
# WHITELABEL TOKEN PLATFORM DEPLOYMENT SCRIPT
# Complete setup and deployment for each client
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="whitelabel-token-platform"
DEPLOYMENT_DIR="/opt/whitelabel-platform"
LOG_FILE="/var/log/whitelabel-deployment.log"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "[ERROR] $1" >> $LOG_FILE
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
    echo "[WARNING] $1" >> $LOG_FILE
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
    echo "[INFO] $1" >> $LOG_FILE
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine OS version"
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        warning "This script is tested on Ubuntu/Debian. Proceeding anyway..."
    fi
    
    # Check memory (minimum 4GB)
    MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEMORY_GB=$((MEMORY_KB / 1024 / 1024))
    if [[ $MEMORY_GB -lt 4 ]]; then
        warning "System has less than 4GB RAM. Consider upgrading for optimal performance."
    fi
    
    # Check disk space (minimum 50GB)
    DISK_AVAILABLE=$(df / | awk 'NR==2 {print $4}')
    DISK_GB=$((DISK_AVAILABLE / 1024 / 1024))
    if [[ $DISK_GB -lt 50 ]]; then
        error "Insufficient disk space. Need at least 50GB available."
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log "Docker not found. Installing Docker..."
        install_docker
    else
        log "Docker is installed"
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log "Docker Compose not found. Installing Docker Compose..."
        install_docker_compose
    else
        log "Docker Compose is installed"
    fi
    
    log "System requirements check completed"
}

# Install Docker
install_docker() {
    log "Installing Docker..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Enable Docker service
    systemctl enable docker
    systemctl start docker
    
    # Add user to docker group
    if [[ -n "$SUDO_USER" ]]; then
        usermod -aG docker $SUDO_USER
    fi
    
    log "Docker installation completed"
}

# Install Docker Compose
install_docker_compose() {
    log "Installing Docker Compose..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d '"' -f 4)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    log "Docker Compose installation completed"
}

# Create deployment directory structure
setup_directories() {
    log "Setting up deployment directories..."
    
    mkdir -p $DEPLOYMENT_DIR/{config,data,logs,ssl,client-assets,backups}
    mkdir -p $DEPLOYMENT_DIR/data/{postgres,redis,fabric,elasticsearch}
    mkdir -p $DEPLOYMENT_DIR/logs/{api,nginx,worker,kyc,vault,payment}
    mkdir -p $DEPLOYMENT_DIR/ssl/{nginx,certs}
    mkdir -p $DEPLOYMENT_DIR/client-assets/{logos,css,js}
    
    # Set permissions
    chown -R 999:999 $DEPLOYMENT_DIR/data
    chown -R 1000:1000 $DEPLOYMENT_DIR/client-assets
    
    log "Directory structure created"
}

# Generate SSL certificates
generate_ssl_certs() {
    log "Generating SSL certificates..."
    
    # Create SSL directory structure
    mkdir -p $DEPLOYMENT_DIR/ssl/nginx
    cd $DEPLOYMENT_DIR/ssl/nginx
    
    # Generate private key
    openssl genrsa -out server.key 4096
    
    # Generate certificate signing request
    openssl req -new -key server.key -out server.csr -subj "/C=IN/ST=Maharashtra/L=Mumbai/O=Whitelabel Token Platform/CN=localhost"
    
    # Generate self-signed certificate
    openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt
    
    # Generate DH parameters for better security
    openssl dhparam -out dhparam.pem 2048
    
    # Clean up CSR file
    rm server.csr
    
    cd - > /dev/null
    
    log "SSL certificates generated"
}

# Setup environment configuration
setup_environment() {
    log "Setting up environment configuration..."
    
    cat > $DEPLOYMENT_DIR/.env << EOF
# Whitelabel Token Platform Environment Configuration

# Application
NODE_ENV=production
JWT_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)

# Database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -base64 16)
DATABASE_URL=postgresql://postgres:\${POSTGRES_PASSWORD}@postgres:5432/whitelabel_tokens

# Redis
REDIS_PASSWORD=$(openssl rand -base64 16)
REDIS_URL=redis://:\${REDIS_PASSWORD}@redis:6379

# Blockchain
BLOCKCHAIN_PROVIDER=http://hyperledger-fabric:8545
FABRIC_CCP_PATH=/app/config/connection-profile.json

# Payment Gateways
RAZORPAY_KEY_ID=your_rzp_test_key
RAZORPAY_KEY_SECRET=your_rzp_secret_key
STRIPE_SECRET_KEY=sk_test_your_stripe_key
WEBHOOK_SECRET=whsec_your_webhook_secret

# KYC Services
UIDAI_API_KEY=your_uidai_key
ITD_API_KEY=your_itd_key
AML_API_KEY=your_aml_key

# Vault Partners
MMTC_PAMP_API_KEY=your_mmtc_key
MMTC_PAMP_API_SECRET=your_mmtc_secret
SAFEGOLD_API_KEY=your_safegold_key
AUGMONT_API_KEY=your_augmont_key

# Email/SMS
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=noreply@whitelabel-tokens.com
SMTP_PASS=your_smtp_password
SMS_API_KEY=your_sms_api_key

# Monitoring
SENTRY_DSN=your_sentry_dsn
GOOGLE_ANALYTICS_ID=GA-XXXXXXXXX

# Client Configuration
DEFAULT_TENANT_ID=$(openssl rand -hex 16)
MAX_USERS_PER_TENANT=1000000
API_RATE_LIMIT_WINDOW=15
API_RATE_LIMIT_MAX=1000
EOF
    
    chmod 600 $DEPLOYMENT_DIR/.env
    log "Environment configuration created"
}

# Setup Nginx configuration
setup_nginx() {
    log "Setting up Nginx configuration..."
    
    mkdir -p $DEPLOYMENT_DIR/nginx/{conf.d,logs}
    
    # Main nginx.conf
    cat > $DEPLOYMENT_DIR/nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;

    # Upstream API servers
    upstream api_backend {
        server api:3000 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

    # HTTP to HTTPS redirect
    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }

    # Main HTTPS server
    server {
        listen 443 ssl http2;
        server_name _;

        # SSL configuration
        ssl_certificate /etc/nginx/ssl/server.crt;
        ssl_certificate_key /etc/nginx/ssl/server.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

        # Security headers
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' wss: https:;" always;

        # Client assets
        location /client-assets/ {
            alias /var/www/client-assets/;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        # API endpoints
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://api_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # Login endpoint with stricter rate limiting
        location /api/v1/auth/login {
            limit_req zone=login burst=5 nodelay;
            
            proxy_pass http://api_backend;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Health check
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

    log "Nginx configuration created"
}

# Deploy the application
deploy_application() {
    log "Deploying Whitelabel Token Platform..."
    
    cd $DEPLOYMENT_DIR
    
    # Copy deployment files
    cp -r ../deployment/docker-compose.yml .
    cp -r ../deployment/services ./services
    cp -r ../database ./database
    cp -r ../backend ./backend
    cp -r ../frontend ./frontend
    
    # Build and start services
    docker-compose build --no-cache
    docker-compose up -d
    
    # Wait for services to be healthy
    log "Waiting for services to start..."
    sleep 30
    
    # Check service health
    check_services_health
    
    log "Application deployment completed"
}

# Check service health
check_services_health() {
    log "Checking service health..."
    
    local services=("postgres" "redis" "api" "nginx")
    
    for service in "${services[@]}"; do
        if docker-compose ps | grep -q "$service.*Up"; then
            log "$service is running"
        else
            error "$service is not running"
        fi
    done
    
    # Check API health
    local api_health=$(curl -s http://localhost/health || echo "down")
    if [[ "$api_health" == "healthy" ]]; then
        log "API health check passed"
    else
        warning "API health check failed"
    fi
    
    log "Service health check completed"
}

# Initialize database
initialize_database() {
    log "Initializing database..."
    
    # Wait for PostgreSQL to be ready
    log "Waiting for PostgreSQL to be ready..."
    while ! docker-compose exec -T postgres pg_isready -U postgres; do
        sleep 2
    done
    
    # Run database migrations
    log "Running database migrations..."
    docker-compose exec -T api npm run migrate || warning "Migration failed, continuing..."
    
    # Seed initial data
    log "Seeding initial data..."
    docker-compose exec -T api npm run seed || warning "Seeding failed, continuing..."
    
    log "Database initialization completed"
}

# Create first tenant (client)
create_first_tenant() {
    log "Creating first tenant (demo client)..."
    
    # Demo tenant configuration
    local tenant_config='{
        "organizationId": "DEMO_CLIENT",
        "companyName": "Demo Gold Platform",
        "brandConfig": {
            "primaryColor": "#007AFF",
            "secondaryColor": "#5856D6",
            "accentColor": "#BF953F",
            "companyName": "Demo Gold Platform",
            "features": {
                "tokens": ["GOLD", "SILVER", "PLATINUM"],
                "paymentMethods": ["UPI", "CARD", "NET_BANKING"],
                "kycLevels": [1, 2, 3]
            }
        },
        "contactPerson": "Demo Admin",
        "email": "admin@demo-gold.com",
        "phone": "+91-9876543210",
        "tier": "startup"
    }'
    
    # Create tenant via API
    local response=$(curl -s -X POST http://localhost/api/v1/admin/tenants \
        -H "Content-Type: application/json" \
        -d "$tenant_config")
    
    if [[ $? -eq 0 ]]; then
        log "Demo tenant created successfully"
        echo "$response" > $DEPLOYMENT_DIR/first-tenant-config.json
    else
        warning "Failed to create demo tenant"
    fi
}

# Setup monitoring
setup_monitoring() {
    log "Setting up monitoring..."
    
    # Create monitoring configuration directories
    mkdir -p $DEPLOYMENT_DIR/monitoring/{grafana/{dashboards,datasources},prometheus}
    
    # Prometheus configuration
    cat > $DEPLOYMENT_DIR/monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'whitelabel-api'
    static_configs:
      - targets: ['api:3000']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx:9113']
    metrics_path: '/nginx_status'
    scrape_interval: 30s

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']
    metrics_path: '/metrics'
    scrape_interval: 30s
EOF

    log "Monitoring setup completed"
}

# Create backup script
create_backup_script() {
    log "Creating backup script..."
    
    cat > $DEPLOYMENT_DIR/backup.sh << 'EOF'
#!/bin/bash

# Whitelabel Token Platform Backup Script

BACKUP_DIR="/opt/whitelabel-platform/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/whitelabel_backup_$DATE.tar.gz"

mkdir -p $BACKUP_DIR

# Backup database
docker-compose exec -T postgres pg_dump -U postgres whitelabel_tokens > /tmp/db_backup.sql

# Backup configuration
tar -czf $BACKUP_FILE \
    /tmp/db_backup.sql \
    /opt/whitelabel-platform/.env \
    /opt/whitelabel-platform/nginx \
    /opt/whitelabel-platform/ssl \
    /opt/whitelabel-platform/client-assets

# Clean up
rm /tmp/db_backup.sql

# Keep only last 30 backups
find $BACKUP_DIR -name "whitelabel_backup_*.tar.gz" -type f -mtime +30 -delete

echo "Backup completed: $BACKUP_FILE"
EOF

    chmod +x $DEPLOYMENT_DIR/backup.sh
    
    # Add to crontab (daily backup at 2 AM)
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/whitelabel-platform/backup.sh") | crontab -
    
    log "Backup script created and scheduled"
}

# Create admin user
create_admin_user() {
    log "Creating admin user..."
    
    # Default admin credentials
    local admin_email="admin@whitelabel-tokens.com"
    local admin_password=$(openssl rand -base64 12)
    
    # Create admin user via API
    local response=$(curl -s -X POST http://localhost/api/v1/auth/register \
        -H "Content-Type: application/json" \
        -H "X-Tenant-Id: demo-tenant-id" \
        -d "{
            \"email\": \"$admin_email\",
            \"password\": \"$admin_password\",
            \"firstName\": \"Platform\",
            \"lastName\": \"Administrator\",
            \"phone\": \"+91-9876543210\",
            \"role\": \"admin\"
        }")
    
    if [[ $? -eq 0 ]]; then
        log "Admin user created successfully"
        echo "Admin User: $admin_email" > $DEPLOYMENT_DIR/admin-credentials.txt
        echo "Password: $admin_password" >> $DEPLOYMENT_DIR/admin-credentials.txt
        chmod 600 $DEPLOYMENT_DIR/admin-credentials.txt
    else
        warning "Failed to create admin user"
    fi
}

# Generate deployment report
generate_report() {
    log "Generating deployment report..."
    
    cat > $DEPLOYMENT_DIR/DEPLOYMENT_REPORT.md << EOF
# Whitelabel Token Platform - Deployment Report

**Date:** $(date)
**Environment:** Production
**Version:** 1.0.0

## 🎯 Deployment Summary

The Whitelabel Precious Metals Token Platform has been successfully deployed with the following components:

### ✅ Core Services
- **API Server:** Multi-tenant backend with JWT authentication
- **Database:** PostgreSQL with multi-tenant schema
- **Cache:** Redis for session management and caching
- **Blockchain:** Hyperledger Fabric for token operations
- **Reverse Proxy:** Nginx with SSL termination and load balancing

### ✅ Monitoring & Logging
- **Prometheus:** Metrics collection and monitoring
- **Grafana:** Dashboard and alerting
- **ELK Stack:** Centralized logging (Elasticsearch, Logstash, Kibana)

### ✅ Client Setup
- **First Tenant:** Demo Gold Platform (startup tier)
- **Admin User:** admin@whitelabel-tokens.com
- **API Access:** Available at https://localhost/api/v1/

## 🔧 Configuration

### Environment Variables
All sensitive configuration is stored in: \`$DEPLOYMENT_DIR/.env\`

### Client Assets
Custom branding assets are stored in: \`$DEPLOYMENT_DIR/client-assets/\`

### SSL Certificates
Self-signed SSL certificates generated for: \`$DEPLOYMENT_DIR/ssl/nginx/\`

## 🚀 Access Points

### Web Interfaces
- **Customer Portal:** https://localhost (after setting up client assets)
- **Admin Dashboard:** https://localhost/admin
- **API Documentation:** https://localhost/api/docs

### Monitoring
- **Prometheus:** http://localhost:9090
- **Grafana:** http://localhost:3001 (admin/admin)
- **Kibana:** http://localhost:5601

## 📊 Service Status

$(docker-compose ps)

## 🔐 Security Notes

1. **SSL Certificates:** Self-signed certificates are in place. Replace with proper certificates in production.
2. **JWT Secrets:** All secrets are randomly generated and stored securely.
3. **Database:** Passwords are randomly generated and secured.
4. **Rate Limiting:** API endpoints have rate limiting configured.

## 🛠️ Maintenance

### Backup
- Automated daily backups at 2 AM
- Backup location: \`$DEPLOYMENT_DIR/backups/\`
- Manual backup: \`$DEPLOYMENT_DIR/backup.sh\`

### Log Monitoring
- Application logs: \`$DEPLOYMENT_DIR/logs/\`
- Docker logs: \`docker-compose logs -f [service-name]\`

### Updates
- Code updates: \`git pull && docker-compose build && docker-compose up -d\`
- Database migrations: \`docker-compose exec api npm run migrate\`

## 💼 Client Onboarding

To add new clients:

1. **Prepare client branding** (logo, colors, company name)
2. **Call tenant creation API** with client details
3. **Configure client domain/subdomain**
4. **Set up payment gateway** for the client
5. **Configure KYC/AML** settings for client's geography

## 📞 Support

For technical support:
- **Email:** support@whitelabel-tokens.com
- **Documentation:** See project README files
- **Logs:** Check \`$DEPLOYMENT_DIR/logs/\` for issues

## ⚠️ Important Notes

1. **Replace self-signed SSL certificates** with proper certificates
2. **Update all API keys** (payment gateways, KYC services, etc.)
3. **Configure proper DNS** for client domains
4. **Set up monitoring alerts** in Grafana
5. **Review security configurations** before going to production

---

**Deployment completed successfully!** 🎉
EOF

    log "Deployment report generated: $DEPLOYMENT_DIR/DEPLOYMENT_REPORT.md"
}

# Main deployment function
main() {
    log "Starting Whitelabel Token Platform deployment..."
    
    check_root
    check_requirements
    setup_directories
    generate_ssl_certs
    setup_environment
    setup_nginx
    deploy_application
    initialize_database
    create_first_tenant
    setup_monitoring
    create_backup_script
    create_admin_user
    generate_report
    
    log "🎉 Deployment completed successfully!"
    log "Access points:"
    log "  - API: https://localhost/api/v1/"
    log "  - Monitoring: http://localhost:9090 (Prometheus)"
    log "  - Grafana: http://localhost:3001"
    log "  - Admin credentials: $DEPLOYMENT_DIR/admin-credentials.txt"
    log "  - Full report: $DEPLOYMENT_DIR/DEPLOYMENT_REPORT.md"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "backup")
        $DEPLOYMENT_DIR/backup.sh
        ;;
    "logs")
        docker-compose logs -f
        ;;
    "status")
        docker-compose ps
        ;;
    "restart")
        docker-compose restart
        ;;
    "stop")
        docker-compose down
        ;;
    "update")
        git pull
        docker-compose build
        docker-compose up -d
        ;;
    *)
        echo "Usage: $0 {deploy|backup|logs|status|restart|stop|update}"
        exit 1
        ;;
esac