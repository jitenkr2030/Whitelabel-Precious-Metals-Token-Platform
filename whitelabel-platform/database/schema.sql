-- ============================================================================
-- WHITELABEL TOKEN PLATFORM DATABASE SCHEMA
-- Multi-tenant architecture for multiple clients
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable JSONB extension for advanced JSON operations
CREATE EXTENSION IF NOT EXISTS "pg_jsonb";

-- ============================================================================
-- CORE TENANT MANAGEMENT
-- ============================================================================

-- Tenants (clients) table - Each row represents a client using the platform
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id VARCHAR(50) UNIQUE NOT NULL, -- Client's unique identifier
    company_name VARCHAR(255) NOT NULL,
    brand_config JSONB, -- Branding configuration (colors, logos, etc.)
    contact_person VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    tier VARCHAR(20) DEFAULT 'lite' CHECK (tier IN ('lite', 'pro', 'startup', 'growth', 'enterprise')),
    api_credentials JSONB, -- API keys and secrets
    subscription_details JSONB, -- Billing and subscription info
    features_enabled JSONB, -- Enabled features for this client
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'cancelled'))
);

-- API credentials for tenant isolation
CREATE TABLE api_credentials (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    api_key VARCHAR(255) UNIQUE NOT NULL,
    api_secret VARCHAR(255) NOT NULL,
    permissions JSONB DEFAULT '{}', -- API permissions and rate limits
    created_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'expired'))
);

-- ============================================================================
-- USER MANAGEMENT
-- ============================================================================

-- Users table - End users of each tenant's platform
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    date_of_birth DATE,
    gender VARCHAR(10),
    aadhaar_number VARCHAR(12),
    pan_number VARCHAR(20),
    role VARCHAR(20) DEFAULT 'user' CHECK (role IN ('user', 'admin', 'super_admin')),
    kyc_status VARCHAR(20) DEFAULT 'pending' CHECK (kyc_status IN ('pending', 'verified', 'rejected', 'expired')),
    kyc_level INTEGER DEFAULT 0 CHECK (kyc_level BETWEEN 0 AND 3),
    verification_documents JSONB, -- KYC document storage
    address JSONB, -- Current address information
    bank_accounts JSONB, -- Bank account details for payouts
    preferences JSONB DEFAULT '{}', -- User preferences and settings
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret VARCHAR(255),
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Unique constraint on email per tenant
CREATE UNIQUE INDEX idx_users_tenant_email ON users(tenant_id, email);

-- ============================================================================
-- ASSET TOKENIZATION
-- ============================================================================

-- Supported asset types
CREATE TABLE asset_types (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(20) UNIQUE NOT NULL, -- GOLD, SILVER, PLATINUM
    name VARCHAR(100) NOT NULL,
    description TEXT,
    purity_standard VARCHAR(20), -- 999, 9999, etc.
    unit VARCHAR(10) DEFAULT 'g', -- grams, kg, etc.
    current_price DECIMAL(15,2), -- Current market price
    price_updated_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert default asset types
INSERT INTO asset_types (code, name, description, purity_standard, unit, current_price) VALUES
('GOLD', '24K Gold', '24 Karat Gold tokens backed by LBMA certified gold', '9999', 'g', 6250.00),
('SILVER', 'Fine Silver', 'Fine Silver tokens with 999 purity', '999', 'g', 57.00),
('PLATINUM', 'Investment Grade Platinum', 'Investment grade platinum tokens', '9995', 'g', 1230.00);

-- User portfolio holdings
CREATE TABLE user_holdings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    asset_type VARCHAR(20) REFERENCES asset_types(code),
    quantity DECIMAL(20,8) NOT NULL, -- Supports fractional tokens
    average_purchase_price DECIMAL(15,2), -- Average purchase price
    current_price DECIMAL(15,2), -- Current market price
    total_value DECIMAL(15,2), -- quantity * current_price
    vault_provider VARCHAR(50), -- MMTC-PAMP, SafeGold, etc.
    certificate_number VARCHAR(100), -- Vault certificate reference
    batch_id VARCHAR(50), -- Tokenization batch identifier
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- TRANSACTION MANAGEMENT
-- ============================================================================

-- Transaction types
CREATE TABLE transaction_types (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(20) UNIQUE NOT NULL, -- BUY, SELL, REDEEM, TRANSFER
    name VARCHAR(100) NOT NULL,
    description TEXT,
    requires_kyc BOOLEAN DEFAULT FALSE,
    requires_payment BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE
);

-- Insert default transaction types
INSERT INTO transaction_types (code, name, description, requires_kyc, requires_payment) VALUES
('BUY', 'Purchase Tokens', 'Purchase digital tokens', TRUE, TRUE),
('SELL', 'Sell Tokens', 'Sell digital tokens for fiat', TRUE, TRUE),
('REDEEM', 'Physical Redemption', 'Redeem tokens for physical assets', TRUE, TRUE),
('TRANSFER', 'Token Transfer', 'Transfer tokens between users', TRUE, FALSE);

-- Main transactions table
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    transaction_type VARCHAR(20) REFERENCES transaction_types(code),
    asset_type VARCHAR(20) REFERENCES asset_types(code),
    quantity DECIMAL(20,8) NOT NULL,
    price DECIMAL(15,2) NOT NULL,
    total_value DECIMAL(15,2) NOT NULL, -- quantity * price
    payment_method VARCHAR(50), -- UPI, CARD, NET_BANKING, etc.
    payment_reference VARCHAR(100), -- Payment gateway reference
    payment_status VARCHAR(20) DEFAULT 'pending', -- pending, completed, failed, refunded
    payment_data JSONB, -- Payment gateway response data
    blockchain_tx_hash VARCHAR(100), -- Blockchain transaction hash
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled', 'refunded')),
    processed_at TIMESTAMP,
    failure_reason TEXT,
    metadata JSONB DEFAULT '{}', -- Additional transaction data
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Transaction history for audit trail
CREATE TABLE transaction_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID REFERENCES transactions(id) ON DELETE CASCADE,
    previous_status VARCHAR(20),
    new_status VARCHAR(20),
    changed_by UUID, -- admin user ID if changed by admin
    change_reason TEXT,
    additional_data JSONB,
    changed_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- PAYMENT PROCESSING
-- ============================================================================

-- Payment methods configuration
CREATE TABLE payment_methods (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    code VARCHAR(20) NOT NULL, -- UPI, CARD, NET_BANKING, WALLET
    name VARCHAR(100) NOT NULL,
    gateway_provider VARCHAR(50), -- Razorpay, Stripe, PayU
    gateway_config JSONB, -- Gateway specific configuration
    is_enabled BOOLEAN DEFAULT TRUE,
    fee_percentage DECIMAL(5,2) DEFAULT 0.00,
    fee_fixed DECIMAL(10,2) DEFAULT 0.00,
    min_amount DECIMAL(15,2) DEFAULT 0.00,
    max_amount DECIMAL(15,2),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Payment transactions
CREATE TABLE payment_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    transaction_id UUID REFERENCES transactions(id) ON DELETE CASCADE,
    payment_method_id UUID REFERENCES payment_methods(id),
    gateway_transaction_id VARCHAR(255), -- Gateway's transaction ID
    gateway_response JSONB, -- Full gateway response
    amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'INR',
    status VARCHAR(20) DEFAULT 'pending', -- pending, processing, completed, failed, cancelled
    processed_at TIMESTAMP,
    refund_amount DECIMAL(15,2) DEFAULT 0.00,
    failure_reason TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- KYC/AML COMPLIANCE
-- ============================================================================

-- KYC document types
CREATE TABLE kyc_document_types (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(20) UNIQUE NOT NULL, -- AADHAAR, PAN, PASSPORT, DL
    name VARCHAR(100) NOT NULL,
    description TEXT,
    verification_required BOOLEAN DEFAULT TRUE,
    is_mandatory BOOLEAN DEFAULT FALSE,
    max_file_size INTEGER DEFAULT 5242880, -- 5MB
    allowed_formats TEXT[] DEFAULT ARRAY['pdf', 'jpg', 'jpeg', 'png'],
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert default KYC document types
INSERT INTO kyc_document_types (code, name, description, verification_required, is_mandatory) VALUES
('AADHAAR', 'Aadhaar Card', 'Indian Aadhaar card for identity verification', TRUE, TRUE),
('PAN', 'PAN Card', 'Permanent Account Number for tax identification', TRUE, TRUE),
('PASSPORT', 'Passport', 'Indian passport for additional verification', TRUE, FALSE),
('DRIVING_LICENSE', 'Driving License', 'Indian driving license for address verification', TRUE, FALSE);

-- KYC verification records
CREATE TABLE kyc_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    document_type UUID REFERENCES kyc_document_types(id),
    document_number VARCHAR(50),
    document_data JSONB, -- Encrypted document data
    address_data JSONB, -- Address information
    verification_status VARCHAR(20) DEFAULT 'pending' CHECK (verification_status IN ('pending', 'processing', 'verified', 'rejected')),
    verification_provider VARCHAR(50), -- UIDAI, etc.
    verification_response JSONB, -- Provider's response
    verifier_notes TEXT,
    verified_by UUID, -- admin user ID
    verified_at TIMESTAMP,
    expires_at TIMESTAMP, -- KYC expiration date
    created_at TIMESTAMP DEFAULT NOW()
);

-- AML monitoring and alerts
CREATE TABLE aml_alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    transaction_id UUID REFERENCES transactions(id) ON DELETE CASCADE,
    alert_type VARCHAR(50), -- HIGH_AMOUNT, SUSPICIOUS_PATTERN, PEP_MATCH, etc.
    risk_score INTEGER CHECK (risk_score BETWEEN 0 AND 100),
    description TEXT,
    status VARCHAR(20) DEFAULT 'open' CHECK (status IN ('open', 'investigating', 'resolved', 'dismissed')),
    assigned_to UUID, -- admin user handling the alert
    resolution_notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);

-- ============================================================================
-- VAULT MANAGEMENT
-- ============================================================================

-- Vault partners/providers
CREATE TABLE vault_providers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(20) UNIQUE NOT NULL, -- MMTC_PAMP, SAFEGOLD, AUGMONT
    name VARCHAR(100) NOT NULL,
    description TEXT,
    api_endpoint VARCHAR(255),
    api_config JSONB, -- API keys and configuration
    is_active BOOLEAN DEFAULT TRUE,
    certification_standards TEXT[], -- LBMA, LPMM, etc.
    supported_assets TEXT[], -- GOLD, SILVER, PLATINUM
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert default vault providers
INSERT INTO vault_providers (code, name, description, certification_standards, supported_assets) VALUES
('MMTC_PAMP', 'MMTC-PAMP', 'MMTC-PAMP is a joint venture between MMTC and PAMP', ARRAY['LBMA'], ARRAY['GOLD', 'SILVER']),
('SAFEGOLD', 'SafeGold', 'SafeGold by PentaGold provides secure gold storage', ARRAY['LBMA'], ARRAY['GOLD']),
('AUGMONT', 'Augmont', 'Augmont provides digital gold storage and trading', ARRAY['LBMA'], ARRAY['GOLD', 'SILVER']);

-- Vault inventory tracking
CREATE TABLE vault_inventory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    provider_id UUID REFERENCES vault_providers(id),
    asset_type VARCHAR(20) REFERENCES asset_types(code),
    serial_number VARCHAR(100), -- Physical asset serial number
    weight_grams DECIMAL(10,4) NOT NULL,
    purity DECIMAL(5,4) NOT NULL, -- 0.9999 for 24K gold
    batch_id VARCHAR(50),
    certificate_url VARCHAR(500),
    insurance_value DECIMAL(15,2),
    storage_location JSONB, -- Vault location details
    tokenized_amount DECIMAL(20,8) DEFAULT 0.00, -- How much is tokenized
    available_amount DECIMAL(20,8) DEFAULT 0.00, -- Available for tokenization
    status VARCHAR(20) DEFAULT 'stored' CHECK (status IN ('stored', 'tokenized', 'redeemed', 'transferred')),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- AUDIT AND COMPLIANCE
-- ============================================================================

-- System audit log
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    entity_type VARCHAR(50), -- USER, TRANSACTION, KYC, etc.
    entity_id UUID, -- ID of the affected entity
    action VARCHAR(50), -- CREATE, UPDATE, DELETE, LOGIN, etc.
    old_values JSONB, -- Previous values (for updates)
    new_values JSONB, -- New values (for creates/updates)
    ip_address INET,
    user_agent TEXT,
    session_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Regulatory reporting
CREATE TABLE regulatory_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    report_type VARCHAR(50), -- FIU, STR, CTR, etc.
    reporting_period_start DATE,
    reporting_period_end DATE,
    report_data JSONB, -- Compiled report data
    file_path VARCHAR(500), -- Path to generated report file
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'generated', 'submitted')),
    submitted_at TIMESTAMP,
    submission_reference VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- NOTIFICATIONS AND COMMUNICATIONS
-- ============================================================================

-- Notification templates
CREATE TABLE notification_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    template_code VARCHAR(50) NOT NULL, -- WELCOME_EMAIL, KYC_APPROVED, etc.
    template_name VARCHAR(100) NOT NULL,
    subject VARCHAR(255),
    content TEXT, -- Template content with placeholders
    template_type VARCHAR(20) DEFAULT 'email' CHECK (template_type IN ('email', 'sms', 'push', 'in_app')),
    is_active BOOLEAN DEFAULT TRUE,
    variables JSONB DEFAULT '{}', -- Available template variables
    created_at TIMESTAMP DEFAULT NOW()
);

-- User notifications
CREATE TABLE user_notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50), -- EMAIL, SMS, PUSH, IN_APP
    category VARCHAR(50), -- TRANSACTION, KYC, SYSTEM, MARKET, etc.
    title VARCHAR(255),
    message TEXT,
    data JSONB DEFAULT '{}', -- Additional notification data
    is_read BOOLEAN DEFAULT FALSE,
    sent_at TIMESTAMP,
    read_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- ANALYTICS AND REPORTING
-- ============================================================================

-- Daily aggregated metrics
CREATE TABLE daily_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    metric_date DATE NOT NULL,
    new_users INTEGER DEFAULT 0,
    total_users INTEGER DEFAULT 0,
    active_users INTEGER DEFAULT 0,
    kyc_verified_users INTEGER DEFAULT 0,
    total_transactions INTEGER DEFAULT 0,
    buy_transactions INTEGER DEFAULT 0,
    sell_transactions INTEGER DEFAULT 0,
    total_volume DECIMAL(15,2) DEFAULT 0.00,
    gold_volume DECIMAL(15,2) DEFAULT 0.00,
    silver_volume DECIMAL(15,2) DEFAULT 0.00,
    platinum_volume DECIMAL(15,2) DEFAULT 0.00,
    revenue DECIMAL(15,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(tenant_id, metric_date)
);

-- ============================================================================
-- INDICES FOR PERFORMANCE
-- ============================================================================

-- User indices
CREATE INDEX idx_users_tenant_id ON users(tenant_id);
CREATE INDEX idx_users_email ON users(tenant_id, email);
CREATE INDEX idx_users_kyc_status ON users(tenant_id, kyc_status);
CREATE INDEX idx_users_created_at ON users(created_at);

-- Transaction indices
CREATE INDEX idx_transactions_tenant_id ON transactions(tenant_id);
CREATE INDEX idx_transactions_user_id ON transactions(user_id);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_type ON transactions(transaction_type);
CREATE INDEX idx_transactions_asset_type ON transactions(asset_type);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);

-- Holding indices
CREATE INDEX idx_holdings_tenant_id ON user_holdings(tenant_id);
CREATE INDEX idx_holdings_user_id ON user_holdings(user_id);
CREATE INDEX idx_holdings_asset_type ON user_holdings(asset_type);

-- Audit indices
CREATE INDEX idx_audit_tenant_id ON audit_logs(tenant_id);
CREATE INDEX idx_audit_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_created_at ON audit_logs(created_at);

-- ============================================================================
-- TRIGGERS FOR AUTOMATIC UPDATES
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add triggers for updated_at
CREATE TRIGGER update_tenants_updated_at BEFORE UPDATE ON tenants FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_holdings_updated_at BEFORE UPDATE ON user_holdings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transactions FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_vault_inventory_updated_at BEFORE UPDATE ON vault_inventory FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to update total_value in holdings
CREATE OR REPLACE FUNCTION update_holding_value()
RETURNS TRIGGER AS $$
BEGIN
    NEW.total_value = NEW.quantity * NEW.current_price;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_holding_value_trigger 
    BEFORE INSERT OR UPDATE ON user_holdings 
    FOR EACH ROW EXECUTE FUNCTION update_holding_value();

-- ============================================================================
-- INITIAL DATA AND SAMPLE DATA
-- ============================================================================

-- Sample tenant (for demonstration)
INSERT INTO tenants (organization_id, company_name, brand_config, contact_person, email, phone, tier) VALUES
('DEMO_CLIENT', 'Demo Gold Token Platform', '{
    "primaryColor": "#007AFF",
    "secondaryColor": "#5856D6", 
    "accentColor": "#BF953F",
    "companyName": "Demo Gold Platform",
    "logoUrl": "/assets/demo-logo.png",
    "features": {
        "tokens": ["GOLD", "SILVER", "PLATINUM"],
        "paymentMethods": ["UPI", "CARD", "NET_BANKING"],
        "kycLevels": [1, 2, 3],
        "maxDailyLimit": 1000000,
        "supportedLanguages": ["en", "hi"]
    }
}', 'Rajesh Kumar', 'admin@demo-gold.com', '+91-9876543210', 'lite');

-- Sample tenants for different package tiers
INSERT INTO tenants (organization_id, company_name, brand_config, contact_person, email, phone, tier, features_enabled) VALUES
('LITE_CLIENT_001', 'City Jewellery Store', '{"primaryColor": "#8B4513", "secondaryColor": "#FFD700", "logo": "city-jewellery-logo.png", "domain": "city-jewellery.whitelabel-tokens.com"}', 'Priya Sharma', 'contact@cityjewellery.com', '+91-9876543211', 'lite', '{"api_access": false, "advanced_analytics": false, "custom_branding": false}'),
('PRO_CLIENT_001', 'GoldTech Solutions', '{"primaryColor": "#2C3E50", "secondaryColor": "#E74C3C", "logo": "goldtech-logo.png", "domain": "goldtech.whitelabel-tokens.com"}', 'Amit Patel', 'info@goldtech.in', '+91-9876543212', 'pro', '{"api_access": true, "advanced_analytics": true, "custom_branding": true}'),
('ENTERPRISE_CLIENT_001', 'Mumbai NBFC Corp', '{"primaryColor": "#1A365D", "secondaryColor": "#3182CE", "logo": "mumbai-nbfc-logo.png", "domain": "secure.mumbainbfc.com"}', 'Suresh Gupta', 'corporate@mumbainbfc.com', '+91-9876543213', 'enterprise', '{"api_access": true, "advanced_analytics": true, "custom_branding": true, "dedicated_infrastructure": true}');

-- Sample payment methods for demo tenant
INSERT INTO payment_methods (tenant_id, code, name, gateway_provider, is_enabled, fee_percentage, fee_fixed) 
SELECT id, 'UPI', 'UPI Payments', 'razorpay', true, 0.5, 0 FROM tenants WHERE organization_id = 'DEMO_CLIENT';

-- Sample notification templates
INSERT INTO notification_templates (tenant_id, template_code, template_name, subject, content, template_type)
SELECT id, 'WELCOME_EMAIL', 'Welcome Email', 'Welcome to {{companyName}}', 
       'Welcome to {{companyName}}! Your account has been created successfully.', 'email'
FROM tenants WHERE organization_id = 'DEMO_CLIENT';

-- ============================================================================
-- VIEWS FOR REPORTING
-- ============================================================================

-- User summary view
CREATE VIEW v_user_summary AS
SELECT 
    t.id as tenant_id,
    t.company_name,
    COUNT(u.id) as total_users,
    COUNT(u.id) FILTER (WHERE u.kyc_status = 'verified') as verified_users,
    COUNT(u.id) FILTER (WHERE u.created_at::date = CURRENT_DATE) as new_today,
    COUNT(u.id) FILTER (WHERE u.last_login_at::date = CURRENT_DATE) as active_today
FROM tenants t
LEFT JOIN users u ON t.id = u.tenant_id
GROUP BY t.id, t.company_name;

-- Transaction summary view
CREATE VIEW v_transaction_summary AS
SELECT 
    t.id as tenant_id,
    t.company_name,
    COUNT(trx.id) as total_transactions,
    COUNT(trx.id) FILTER (WHERE trx.transaction_type = 'BUY') as buy_transactions,
    COUNT(trx.id) FILTER (WHERE trx.transaction_type = 'SELL') as sell_transactions,
    COALESCE(SUM(trx.total_value) FILTER (WHERE trx.transaction_type = 'BUY'), 0) as total_buy_volume,
    COALESCE(SUM(trx.total_value) FILTER (WHERE trx.transaction_type = 'SELL'), 0) as total_sell_volume,
    COALESCE(SUM(trx.total_value), 0) as total_volume
FROM tenants t
LEFT JOIN transactions trx ON t.id = trx.tenant_id AND trx.status = 'completed'
GROUP BY t.id, t.company_name;

-- Portfolio summary view
CREATE VIEW v_portfolio_summary AS
SELECT 
    t.id as tenant_id,
    t.company_name,
    u.id as user_id,
    u.first_name || ' ' || u.last_name as user_name,
    h.asset_type,
    h.quantity,
    h.current_price,
    h.total_value
FROM tenants t
JOIN users u ON t.id = u.tenant_id
JOIN user_holdings h ON u.id = h.user_id AND t.id = h.tenant_id
WHERE h.quantity > 0;

-- ============================================================================
-- SECURITY AND PERMISSIONS
-- ============================================================================

-- Row Level Security (RLS) policies
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_holdings ENABLE ROW LEVEL SECURITY;
ALTER TABLE kyc_records ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only access their own data within their tenant
CREATE POLICY users_tenant_policy ON users
    FOR ALL TO authenticated
    USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

CREATE POLICY transactions_tenant_policy ON transactions
    FOR ALL TO authenticated
    USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

CREATE POLICY holdings_tenant_policy ON user_holdings
    FOR ALL TO authenticated
    USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

-- ============================================================================
-- COMMENTS AND DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE tenants IS 'Client organizations using the whitelabel platform';
COMMENT ON TABLE users IS 'End users of each client platform';
COMMENT ON TABLE transactions IS 'All trading and transaction records';
COMMENT ON TABLE user_holdings IS 'User portfolio holdings of tokenized assets';
COMMENT ON TABLE kyc_records IS 'KYC verification records for compliance';
COMMENT ON TABLE vault_inventory IS 'Physical asset inventory stored in partner vaults';

COMMENT ON COLUMN tenants.brand_config IS 'JSON configuration for client branding (colors, logos, company name, etc.)';
COMMENT ON COLUMN users.kyc_status IS 'KYC verification status: pending, verified, rejected, expired';
COMMENT ON COLUMN transactions.status IS 'Transaction status: pending, processing, completed, failed, cancelled';
COMMENT ON COLUMN user_holdings.quantity IS 'Decimal quantity supporting fractional token ownership';

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================