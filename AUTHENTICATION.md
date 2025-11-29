# StreamSets Authentication Configuration

## Current Configuration

- **Version**: StreamSets Data Collector 3.22.3 (Open Source - No Activation Required)
- **Authentication Type**: File-based authentication
- **HTTP Authentication**: Form-based

## Default Users

The following default user accounts are available:

| Username | Password | Role | Description |
|----------|----------|------|-------------|
| admin | admin | Admin | Full access to all features |
| manager | manager | Manager | Start/stop pipelines, monitor, alerts |
| creator | creator | Creator | Create/configure pipelines |
| guest | guest | Guest | View-only access |

### Additional Development/Test Users

| Username | Password | Roles | Group |
|----------|----------|-------|-------|
| user1 | user1 | Manager, Creator | dev |
| user2 | user2 | Manager, Creator | dev |
| user3 | user3 | Manager, Creator | test |
| user4 | user4 | Manager, Creator | test |

## Roles and Permissions

### Admin Role
- Activate Data Collector
- Restart and shutdown Data Collector
- View metrics
- Enable Control Hub
- Install libraries using Package Manager
- Generate support bundles
- All permissions below

### Manager Role
- Start and stop pipelines
- Monitor pipelines
- Configure and reset alerts
- Take, review, and manage snapshots

### Creator Role
- Create and configure pipelines
- Configure alerts
- Preview data
- Monitor pipelines
- Import pipelines

### Guest Role
- View pipelines and alerts
- View monitoring information
- Export pipelines

## Changing Passwords

Users can change their own password after logging in:

1. Click the User icon in the top right
2. Select "Change Password"
3. Enter current password and new password
4. Click Save

## Security Recommendations

### For Production Use:

1. **Change Default Passwords**
   - Immediately change all default user passwords
   - Use strong passwords (minimum 12 characters, mix of upper/lower/numbers/symbols)

2. **Remove Unused Accounts**
   - Delete or disable user accounts that are not needed
   - Especially the test users (user1-user4)

3. **Use HTTPS**
   - Already configured with Let's Encrypt SSL certificate
   - Access: https://streamsets.archse.eng.br

4. **Configure Pipeline Permissions**
   - Assign read/write/execute permissions per pipeline
   - Use groups to manage permissions for multiple users

## Why Version 3.22.3?

Version 3.22.3 is the last fully open-source version that does not require:
- Activation code
- StreamSets account
- Control Hub connection

**Advantages:**
- No activation required
- Free forever
- Stable and production-ready
- Full feature set for data pipelines

**Trade-offs:**
- Older UI
- Missing some newer features from 5.x
- No built-in Control Hub integration

## Alternative: Upgrade to 5.11.0 with Activation

If you need features from version 5.11.0:

1. Create free StreamSets account at: https://streamsets.com/getting-started/
2. Generate activation code
3. Configure in secrets:
   ```yaml
   activation-id: "your-id"
   activation-code: "your-code"
   ```
4. Update deployment image to `streamsets/datacollector:5.11.0`
5. Add environment variables for activation

See `ACTIVATION.md` for detailed instructions.

## Access Information

- **URL**: https://streamsets.archse.eng.br
- **Default Username**: `admin`
- **Default Password**: `admin` (change immediately!)

## Troubleshooting

If you cannot log in:

1. Check pod logs:
   ```bash
   kubectl logs -n streamsets -l app=streamsets
   ```

2. Verify service is running:
   ```bash
   kubectl get pods -n streamsets
   kubectl get svc -n streamsets
   ```

3. Test local access:
   ```bash
   kubectl port-forward -n streamsets svc/streamsets-service 18630:18630
   # Access: http://localhost:18630
   ```
