/**
 * Whitelabel Precious Metals Token Platform
 * Backend API - Multi-Tenant Architecture
 * 
 * Built for multiple clients: Jewellers, Gold/Silver dealers, 
 * Bullion traders, Vault companies, NBFCs, Loan apps, Fintech apps, Crypto exchanges
 */

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { Pool } = require('pg');
const redis = require('redis');
const Web3 = require('web3');
const { v4: uuidv4 } = require('uuid');

// Environment variables
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors({
    origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
    credentials: true
}));

// Rate limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api', limiter);

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Database connections
const pgPool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

const redisClient = redis.createClient({
    url: process.env.REDIS_URL
});

// Blockchain connection
let web3;
if (process.env.BLOCKCHAIN_PROVIDER) {
    web3 = new Web3(new Web3.providers.HttpProvider(process.env.BLOCKCHAIN_PROVIDER));
}

// Tenant validation middleware
async function validateTenant(req, res, next) {
    try {
        const tenantId = req.headers['x-tenant-id'];
        const organizationId = req.headers['x-org-id'];
        
        if (!tenantId) {
            return res.status(400).json({ error: 'Missing tenant ID' });
        }
        
        // Get tenant configuration
        const tenantResult = await pgPool.query(
            'SELECT * FROM tenants WHERE id = $1 AND status = $2',
            [tenantId, 'active']
        );
        
        if (tenantResult.rows.length === 0) {
            return res.status(403).json({ error: 'Invalid or inactive tenant' });
        }
        
        req.tenant = tenantResult.rows[0];
        next();
    } catch (error) {
        console.error('Tenant validation error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
}

// JWT authentication middleware
function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    
    if (!token) {
        return res.status(401).json({ error: 'Access token required' });
    }
    
    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ error: 'Invalid token' });
        }
        req.user = user;
        next();
    });
}

// ============================================================================
// TENANT MANAGEMENT
// ============================================================================

/**
 * Create new tenant (client onboarding)
 */
app.post('/api/v1/admin/tenants', async (req, res) => {
    try {
        const {
            organizationId,
            companyName,
            brandConfig,
            contactPerson,
            email,
            phone,
            tier // startup, growth, enterprise
        } = req.body;
        
        // Create tenant
        const tenantId = uuidv4();
        const tenantResult = await pgPool.query(
            `INSERT INTO tenants (id, organization_id, company_name, brand_config, 
             contact_person, email, phone, tier, created_at, status) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), $9) 
             RETURNING *`,
            [tenantId, organizationId, companyName, brandConfig, 
             contactPerson, email, phone, tier, 'active']
        );
        
        // Create default admin user
        const adminUserId = uuidv4();
        await pgPool.query(
            `INSERT INTO users (id, tenant_id, email, phone, role, kyc_status, created_at) 
             VALUES ($1, $2, $3, $4, $5, $6, NOW())`,
            [adminUserId, tenantId, email, phone, 'admin', 'verified']
        );
        
        // Generate API credentials
        const apiKey = `wl_${organizationId}_${uuidv4().slice(0, 8)}`;
        const apiSecret = uuidv4().replace(/-/g, '').slice(0, 32);
        
        await pgPool.query(
            `INSERT INTO api_credentials (tenant_id, api_key, api_secret, created_at, status) 
             VALUES ($1, $2, $3, NOW(), 'active')`,
            [tenantId, apiKey, apiSecret]
        );
        
        // Set up tenant-specific database schema
        await setupTenantDatabase(tenantId, organizationId);
        
        res.status(201).json({
            message: 'Tenant created successfully',
            tenant: tenantResult.rows[0],
            credentials: {
                apiKey,
                apiSecret,
                tenantId,
                organizationId
            }
        });
        
    } catch (error) {
        console.error('Error creating tenant:', error);
        res.status(500).json({ error: 'Failed to create tenant' });
    }
});

/**
 * Get tenant configuration
 */
app.get('/api/v1/tenant/config', validateTenant, async (req, res) => {
    try {
        const brandConfig = req.tenant.brand_config;
        res.json({
            tenantId: req.tenant.id,
            organizationId: req.tenant.organization_id,
            companyName: req.tenant.company_name,
            brand: brandConfig,
            features: brandConfig.features || {},
            apiVersion: 'v1',
            createdAt: req.tenant.created_at
        });
    } catch (error) {
        console.error('Error fetching tenant config:', error);
        res.status(500).json({ error: 'Failed to fetch tenant configuration' });
    }
});

// ============================================================================
// USER MANAGEMENT
// ============================================================================

/**
 * User registration
 */
app.post('/api/v1/auth/register', validateTenant, async (req, res) => {
    try {
        const {
            email,
            phone,
            password,
            firstName,
            lastName,
            aadhaarNumber,
            panNumber
        } = req.body;
        
        // Check if user exists
        const existingUser = await pgPool.query(
            'SELECT id FROM users WHERE tenant_id = $1 AND email = $2',
            [req.tenant.id, email]
        );
        
        if (existingUser.rows.length > 0) {
            return res.status(400).json({ error: 'User already exists' });
        }
        
        // Hash password
        const hashedPassword = await bcrypt.hash(password, 10);
        
        // Create user
        const userId = uuidv4();
        const userResult = await pgPool.query(
            `INSERT INTO users (id, tenant_id, email, phone, password_hash, 
             first_name, last_name, aadhaar_number, pan_number, role, 
             kyc_status, created_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW()) 
             RETURNING id, email, phone, first_name, last_name, kyc_status`,
            [userId, req.tenant.id, email, phone, hashedPassword, 
             firstName, lastName, aadhaarNumber, panNumber, 'user', 'pending']
        );
        
        // Generate JWT token
        const token = jwt.sign(
            { userId, tenantId: req.tenant.id, email, role: 'user' },
            process.env.JWT_SECRET,
            { expiresIn: '24h' }
        );
        
        res.status(201).json({
            message: 'User registered successfully',
            user: userResult.rows[0],
            token
        });
        
    } catch (error) {
        console.error('Error registering user:', error);
        res.status(500).json({ error: 'Registration failed' });
    }
});

/**
 * User login
 */
app.post('/api/v1/auth/login', validateTenant, async (req, res) => {
    try {
        const { email, password } = req.body;
        
        // Get user
        const userResult = await pgPool.query(
            'SELECT * FROM users WHERE tenant_id = $1 AND email = $2',
            [req.tenant.id, email]
        );
        
        if (userResult.rows.length === 0) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }
        
        const user = userResult.rows[0];
        
        // Verify password
        const validPassword = await bcrypt.compare(password, user.password_hash);
        if (!validPassword) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }
        
        // Generate JWT token
        const token = jwt.sign(
            { 
                userId: user.id, 
                tenantId: req.tenant.id, 
                email: user.email, 
                role: user.role 
            },
            process.env.JWT_SECRET,
            { expiresIn: '24h' }
        );
        
        res.json({
            message: 'Login successful',
            user: {
                id: user.id,
                email: user.email,
                phone: user.phone,
                firstName: user.first_name,
                lastName: user.last_name,
                kycStatus: user.kyc_status,
                role: user.role
            },
            token
        });
        
    } catch (error) {
        console.error('Error logging in user:', error);
        res.status(500).json({ error: 'Login failed' });
    }
});

/**
 * Get user profile
 */
app.get('/api/v1/user/profile', validateTenant, authenticateToken, async (req, res) => {
    try {
        const userResult = await pgPool.query(
            'SELECT id, email, phone, first_name, last_name, kyc_status, role, created_at FROM users WHERE tenant_id = $1 AND id = $2',
            [req.tenant.id, req.user.userId]
        );
        
        if (userResult.rows.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }
        
        res.json({ user: userResult.rows[0] });
    } catch (error) {
        console.error('Error fetching user profile:', error);
        res.status(500).json({ error: 'Failed to fetch profile' });
    }
});

// ============================================================================
// PORTFOLIO MANAGEMENT
// ============================================================================

/**
 * Get user portfolio
 */
app.get('/api/v1/portfolio', validateTenant, authenticateToken, async (req, res) => {
    try {
        // Get token holdings
        const holdingsResult = await pgPool.query(
            `SELECT asset_type, quantity, current_price, total_value, created_at 
             FROM user_holdings 
             WHERE tenant_id = $1 AND user_id = $2 
             ORDER BY created_at DESC`,
            [req.tenant.id, req.user.userId]
        );
        
        // Calculate portfolio summary
        const totalValue = holdingsResult.rows.reduce((sum, holding) => 
            sum + parseFloat(holding.total_value), 0
        );
        
        const goldValue = holdingsResult.rows
            .filter(h => h.asset_type === 'GOLD')
            .reduce((sum, h) => sum + parseFloat(h.total_value), 0);
        
        const silverValue = holdingsResult.rows
            .filter(h => h.asset_type === 'SILVER')
            .reduce((sum, h) => sum + parseFloat(h.total_value), 0);
        
        const platinumValue = holdingsResult.rows
            .filter(h => h.asset_type === 'PLATINUM')
            .reduce((sum, h) => sum + parseFloat(h.total_value), 0);
        
        res.json({
            portfolio: holdingsResult.rows,
            summary: {
                totalValue,
                goldValue,
                silverValue,
                platinumValue,
                lastUpdated: new Date().toISOString()
            }
        });
    } catch (error) {
        console.error('Error fetching portfolio:', error);
        res.status(500).json({ error: 'Failed to fetch portfolio' });
    }
});

// ============================================================================
// TRADING OPERATIONS
// ============================================================================

/**
 * Buy tokens
 */
app.post('/api/v1/trade/buy', validateTenant, authenticateToken, async (req, res) => {
    try {
        const { assetType, quantity, price, paymentMethod, paymentRef } = req.body;
        
        // Validate KYC status
        const userResult = await pgPool.query(
            'SELECT kyc_status FROM users WHERE tenant_id = $1 AND id = $2',
            [req.tenant.id, req.user.userId]
        );
        
        if (userResult.rows[0]?.kyc_status !== 'verified') {
            return res.status(400).json({ error: 'KYC verification required' });
        }
        
        // Create transaction record
        const transactionId = uuidv4();
        const totalValue = quantity * price;
        
        await pgPool.query(
            `INSERT INTO transactions (id, tenant_id, user_id, transaction_type, 
             asset_type, quantity, price, total_value, payment_method, 
             payment_reference, status, created_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())`,
            [transactionId, req.tenant.id, req.user.userId, 'BUY', assetType, 
             quantity, price, totalValue, paymentMethod, paymentRef, 'pending']
        );
        
        // Process payment (simplified - integrate with actual payment gateway)
        const paymentSuccess = await processPayment({
            amount: totalValue,
            method: paymentMethod,
            reference: paymentRef,
            userId: req.user.userId
        });
        
        if (paymentSuccess) {
            // Update transaction status
            await pgPool.query(
                'UPDATE transactions SET status = $1 WHERE id = $2',
                ['completed', transactionId]
            );
            
            // Add tokens to user holdings
            await addTokensToPortfolio(req.tenant.id, req.user.userId, assetType, quantity);
            
            res.json({
                message: 'Purchase successful',
                transactionId,
                assetType,
                quantity,
                totalValue,
                status: 'completed'
            });
        } else {
            // Update transaction status
            await pgPool.query(
                'UPDATE transactions SET status = $1 WHERE id = $2',
                ['failed', transactionId]
            );
            
            res.status(400).json({ error: 'Payment failed' });
        }
        
    } catch (error) {
        console.error('Error processing buy order:', error);
        res.status(500).json({ error: 'Buy order failed' });
    }
});

/**
 * Sell tokens
 */
app.post('/api/v1/trade/sell', validateTenant, authenticateToken, async (req, res) => {
    try {
        const { assetType, quantity, price, paymentMethod } = req.body;
        
        // Check sufficient holdings
        const holdingResult = await pgPool.query(
            'SELECT quantity FROM user_holdings WHERE tenant_id = $1 AND user_id = $2 AND asset_type = $3',
            [req.tenant.id, req.user.userId, assetType]
        );
        
        if (holdingResult.rows.length === 0 || holdingResult.rows[0].quantity < quantity) {
            return res.status(400).json({ error: 'Insufficient holdings' });
        }
        
        // Create transaction record
        const transactionId = uuidv4();
        const totalValue = quantity * price;
        
        await pgPool.query(
            `INSERT INTO transactions (id, tenant_id, user_id, transaction_type, 
             asset_type, quantity, price, total_value, payment_method, status, created_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())`,
            [transactionId, req.tenant.id, req.user.userId, 'SELL', assetType, 
             quantity, price, totalValue, paymentMethod, 'pending']
        );
        
        // Process payout (simplified)
        const payoutSuccess = await processPayout({
            amount: totalValue,
            method: paymentMethod,
            userId: req.user.userId
        });
        
        if (payoutSuccess) {
            // Update transaction status
            await pgPool.query(
                'UPDATE transactions SET status = $1 WHERE id = $2',
                ['completed', transactionId]
            );
            
            // Remove tokens from user holdings
            await removeTokensFromPortfolio(req.tenant.id, req.user.userId, assetType, quantity);
            
            res.json({
                message: 'Sale successful',
                transactionId,
                assetType,
                quantity,
                totalValue,
                status: 'completed'
            });
        } else {
            // Update transaction status
            await pgPool.query(
                'UPDATE transactions SET status = $1 WHERE id = $2',
                ['failed', transactionId]
            );
            
            res.status(400).json({ error: 'Payout failed' });
        }
        
    } catch (error) {
        console.error('Error processing sell order:', error);
        res.status(500).json({ error: 'Sell order failed' });
    }
});

// ============================================================================
// KYC/AML COMPLIANCE
// ============================================================================

/**
 * Submit KYC documents
 */
app.post('/api/v1/kyc/submit', validateTenant, authenticateToken, async (req, res) => {
    try {
        const { documentType, documentNumber, documentData, addressData } = req.body;
        
        // Store KYC documents
        const kycId = uuidv4();
        await pgPool.query(
            `INSERT INTO kyc_records (id, tenant_id, user_id, document_type, 
             document_number, document_data, address_data, status, created_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
            [kycId, req.tenant.id, req.user.userId, documentType, 
             documentNumber, documentData, addressData, 'pending']
        );
        
        // Trigger KYC verification (integrate with actual KYC service)
        const verificationResult = await triggerKYCVerification({
            tenantId: req.tenant.id,
            userId: req.user.userId,
            kycId,
            documentData,
            addressData
        });
        
        res.json({
            message: 'KYC documents submitted successfully',
            kycId,
            status: 'pending_verification'
        });
        
    } catch (error) {
        console.error('Error submitting KYC:', error);
        res.status(500).json({ error: 'KYC submission failed' });
    }
});

// ============================================================================
// ADMIN ENDPOINTS
// ============================================================================

/**
 * Get dashboard metrics
 */
app.get('/api/v1/admin/dashboard', validateTenant, authenticateToken, async (req, res) => {
    try {
        if (req.user.role !== 'admin') {
            return res.status(403).json({ error: 'Admin access required' });
        }
        
        // Get user metrics
        const userMetrics = await pgPool.query(
            `SELECT 
                COUNT(*) as total_users,
                COUNT(*) FILTER (WHERE kyc_status = 'verified') as verified_users,
                COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE) as new_today
             FROM users WHERE tenant_id = $1`,
            [req.tenant.id]
        );
        
        // Get trading metrics
        const tradingMetrics = await pgPool.query(
            `SELECT 
                COUNT(*) as total_transactions,
                COUNT(*) FILTER (WHERE transaction_type = 'BUY') as buy_orders,
                COUNT(*) FILTER (WHERE transaction_type = 'SELL') as sell_orders,
                COALESCE(SUM(total_value) FILTER (WHERE transaction_type = 'BUY'), 0) as total_buy_volume,
                COALESCE(SUM(total_value) FILTER (WHERE transaction_type = 'SELL'), 0) as total_sell_volume
             FROM transactions WHERE tenant_id = $1 AND status = 'completed'`,
            [req.tenant.id]
        );
        
        // Get asset breakdown
        const assetBreakdown = await pgPool.query(
            `SELECT 
                asset_type,
                COUNT(*) as transaction_count,
                SUM(quantity) as total_quantity,
                SUM(total_value) as total_value
             FROM transactions 
             WHERE tenant_id = $1 AND status = 'completed'
             GROUP BY asset_type`,
            [req.tenant.id]
        );
        
        res.json({
            metrics: {
                users: userMetrics.rows[0],
                trading: tradingMetrics.rows[0],
                assets: assetBreakdown.rows
            }
        });
        
    } catch (error) {
        console.error('Error fetching dashboard metrics:', error);
        res.status(500).json({ error: 'Failed to fetch dashboard data' });
    }
});

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Set up tenant-specific database schema
 */
async function setupTenantDatabase(tenantId, organizationId) {
    // Create tenant-specific tables
    const createTablesSQL = `
        -- User holdings for this tenant
        CREATE TABLE IF NOT EXISTS user_holdings_${organizationId} (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID REFERENCES tenants(id),
            user_id UUID,
            asset_type VARCHAR(20),
            quantity DECIMAL(20,8),
            current_price DECIMAL(15,2),
            total_value DECIMAL(15,2),
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        );
        
        -- Tenant-specific transactions
        CREATE TABLE IF NOT EXISTS transactions_${organizationId} (
            id UUID PRIMARY KEY,
            tenant_id UUID REFERENCES tenants(id),
            user_id UUID,
            transaction_type VARCHAR(20),
            asset_type VARCHAR(20),
            quantity DECIMAL(20,8),
            price DECIMAL(15,2),
            total_value DECIMAL(15,2),
            payment_method VARCHAR(50),
            payment_reference VARCHAR(100),
            status VARCHAR(20),
            created_at TIMESTAMP DEFAULT NOW()
        );
    `;
    
    try {
        await pgPool.query(createTablesSQL);
        console.log(`Database schema created for tenant: ${tenantId}`);
    } catch (error) {
        console.error('Error setting up tenant database:', error);
        throw error;
    }
}

/**
 * Add tokens to user portfolio
 */
async function addTokensToPortfolio(tenantId, userId, assetType, quantity) {
    const holdingResult = await pgPool.query(
        'SELECT quantity FROM user_holdings WHERE tenant_id = $1 AND user_id = $2 AND asset_type = $3',
        [tenantId, userId, assetType]
    );
    
    if (holdingResult.rows.length > 0) {
        // Update existing holding
        const currentQuantity = parseFloat(holdingResult.rows[0].quantity);
        const newQuantity = currentQuantity + parseFloat(quantity);
        
        await pgPool.query(
            'UPDATE user_holdings SET quantity = $1, updated_at = NOW() WHERE tenant_id = $2 AND user_id = $3 AND asset_type = $4',
            [newQuantity, tenantId, userId, assetType]
        );
    } else {
        // Create new holding
        await pgPool.query(
            'INSERT INTO user_holdings (tenant_id, user_id, asset_type, quantity, current_price, total_value) VALUES ($1, $2, $3, $4, $5, $6)',
            [tenantId, userId, assetType, quantity, 0, 0]
        );
    }
}

/**
 * Remove tokens from user portfolio
 */
async function removeTokensFromPortfolio(tenantId, userId, assetType, quantity) {
    const holdingResult = await pgPool.query(
        'SELECT quantity FROM user_holdings WHERE tenant_id = $1 AND user_id = $2 AND asset_type = $3',
        [tenantId, userId, assetType]
    );
    
    if (holdingResult.rows.length > 0) {
        const currentQuantity = parseFloat(holdingResult.rows[0].quantity);
        const newQuantity = currentQuantity - parseFloat(quantity);
        
        if (newQuantity <= 0) {
            // Remove holding if quantity becomes zero or negative
            await pgPool.query(
                'DELETE FROM user_holdings WHERE tenant_id = $1 AND user_id = $2 AND asset_type = $3',
                [tenantId, userId, assetType]
            );
        } else {
            // Update quantity
            await pgPool.query(
                'UPDATE user_holdings SET quantity = $1, updated_at = NOW() WHERE tenant_id = $2 AND user_id = $3 AND asset_type = $4',
                [newQuantity, tenantId, userId, assetType]
            );
        }
    }
}

/**
 * Process payment (simplified implementation)
 */
async function processPayment({ amount, method, reference, userId }) {
    // Integrate with actual payment gateway (Razorpay, Stripe, etc.)
    // This is a placeholder implementation
    console.log(`Processing payment: ${amount} via ${method} for user ${userId}`);
    
    // Simulate payment processing
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    return Math.random() > 0.1; // 90% success rate for demo
}

/**
 * Process payout (simplified implementation)
 */
async function processPayout({ amount, method, userId }) {
    // Integrate with actual payout service
    console.log(`Processing payout: ${amount} via ${method} for user ${userId}`);
    
    // Simulate payout processing
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    return Math.random() > 0.05; // 95% success rate for demo
}

/**
 * Trigger KYC verification
 */
async function triggerKYCVerification({ tenantId, userId, kycId, documentData, addressData }) {
    // Integrate with actual KYC service (UIDAI, etc.)
    console.log(`Triggering KYC verification for user ${userId}`);
    
    // Simulate KYC processing
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Randomly approve/reject for demo
    const approved = Math.random() > 0.2; // 80% approval rate
    
    if (approved) {
        await pgPool.query(
            'UPDATE users SET kyc_status = $1 WHERE tenant_id = $2 AND id = $3',
            ['verified', tenantId, userId]
        );
        
        await pgPool.query(
            'UPDATE kyc_records SET status = $1 WHERE id = $2',
            ['approved', kycId]
        );
    }
    
    return { approved };
}

// ============================================================================
// ERROR HANDLING
// ============================================================================

app.use((error, req, res, next) => {
    console.error('Unhandled error:', error);
    res.status(500).json({ error: 'Internal server error' });
});

app.use((req, res) => {
    res.status(404).json({ error: 'Endpoint not found' });
});

// ============================================================================
// SERVER STARTUP
// ============================================================================

async function startServer() {
    try {
        // Connect to Redis
        await redisClient.connect();
        console.log('✅ Connected to Redis');
        
        // Start server
        app.listen(PORT, () => {
            console.log(`🚀 Whitelabel Token Platform API running on port ${PORT}`);
            console.log(`📊 Multi-tenant mode enabled`);
            console.log(`🏢 Target clients: Jewellers, Dealers, Traders, Vaults, NBFCs, Fintechs`);
            console.log(`💰 Pricing: White Label Lite (₹25K-75K setup), Pro (₹1L-2.5L setup), Enterprise (₹10L-50L setup)`);
        });
        
    } catch (error) {
        console.error('❌ Failed to start server:', error);
        process.exit(1);
    }
}

// Handle graceful shutdown
process.on('SIGTERM', async () => {
    console.log('🛑 Received SIGTERM, shutting down gracefully');
    await redisClient.quit();
    process.exit(0);
});

process.on('SIGINT', async () => {
    console.log('🛑 Received SIGINT, shutting down gracefully');
    await redisClient.quit();
    process.exit(0);
});

// Start the server
startServer();

module.exports = app;