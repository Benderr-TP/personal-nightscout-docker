# Creating Cloudflare API Token for Tunnel Setup

## Step-by-Step Guide

### 1. Access Cloudflare Dashboard
- Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
- Log in to your account

### 2. Navigate to API Tokens
- Click on your profile icon (top right)
- Select "My Profile"
- Go to "API Tokens" tab

### 3. Create New Token
- Click "Create Token"
- Choose "Use custom template"
- Or select "Cloudflare Tunnel" template if available

### 4. Configure Token Permissions

**Required Permissions:**
- **Zone Resources**: Include → All zones (or specific zones)
- **Zone Permissions**: 
  - Zone:Read
  - DNS:Edit
- **Account Resources**: Include → All accounts
- **Account Permissions**:
  - Cloudflare Tunnel:Edit
  - Cloudflare Tunnel:Read

### 5. Set Token TTL (Optional)
- **Token TTL**: Set expiration (recommended for security)
- **Client IP Address Filtering**: Optional additional security

### 6. Create and Copy Token
- Click "Continue to summary"
- Review permissions
- Click "Create Token"
- **Copy the token immediately** (you won't see it again)

## Security Best Practices

1. **Use specific zone permissions** instead of "All zones" when possible
2. **Set token expiration** (30-90 days recommended)
3. **Use IP filtering** if your server has a static IP
4. **Store tokens securely** - never commit to version control
5. **Rotate tokens regularly**

## Using the Token

When running `./setup-cloudflare.sh`:
1. Choose option 2 (API token authentication)
2. Paste your API token when prompted
3. The token will be stored securely in `~/.cloudflared/config.yml`

## Multiple Instances

For multiple Nightscout instances:
- Create separate tunnels with different names
- Use different subdomains (e.g., `nightscout1.yourdomain.com`, `nightscout2.yourdomain.com`)
- The same API token can manage multiple tunnels

## Troubleshooting

**Token not working?**
- Check token permissions
- Verify token hasn't expired
- Ensure domain is managed by Cloudflare
- Check token has correct zone permissions

**Permission denied errors?**
- Verify token has "Cloudflare Tunnel:Edit" permission
- Check if token has access to the specific zone
- Ensure domain is in the correct Cloudflare account 