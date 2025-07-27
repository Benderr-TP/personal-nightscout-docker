# Nightscout MongoDB Migration Guide

This guide helps you migrate your Nightscout database from MongoDB Atlas to a self-hosted MongoDB instance. Based on official Nightscout documentation and MongoDB best practices.

## Prerequisites

- MongoDB Database Tools (mongodump/mongorestore) installed
- Access to your MongoDB Atlas connection string (mongodb+srv:// format)
- Access to your new VM/server with MongoDB
- Sufficient disk space for temporary export files
- Consider scheduling during maintenance window for data consistency

## Step 1: Export from MongoDB Atlas

Use the `export-atlas-db.sh` script to export your database:

```bash
# Basic export
./export-atlas-db.sh -c "mongodb+srv://username:password@cluster.mongodb.net/" -d nightscout

# Export with oplog for point-in-time consistency (recommended)
./export-atlas-db.sh -c "mongodb+srv://username:password@cluster.mongodb.net/" -d nightscout --oplog
```

### Parameters:
- `-c`: Your MongoDB Atlas connection string (include credentials)
- `-d`: Database name (default: nightscout)
- `-o`: Output directory (optional, defaults to timestamped directory)
- `--oplog`: Include oplog for data consistency during export (recommended)

### Atlas Connection String Requirements:
- Must use `mongodb+srv://` format for Atlas
- Username/password should only contain letters and numbers (no special characters)
- Format: `mongodb+srv://username:password@cluster0.xxxxx.mongodb.net/`

### Example Atlas connection strings:
```
mongodb+srv://nightscout:mypassword123@cluster0.abcde.mongodb.net/
mongodb+srv://nightscout:mypassword123@cluster0.abcde.mongodb.net/nightscout
```

**Important**: Atlas M0 free tier has 512MB limit and is for testing only, not production.

## Step 2: Transfer Data to New VM

Copy the exported data to your new server:

```bash
# Using scp
scp -r ./nightscout-export-* user@your-vm-ip:/path/to/destination/

# Using rsync
rsync -av ./nightscout-export-* user@your-vm-ip:/path/to/destination/
```

## Step 3: Import to New MongoDB Instance

On your new VM, use the `import-to-vm.sh` script:

```bash
# Basic import to local MongoDB
./import-to-vm.sh -d ./nightscout-export-20240127/nightscout -t mongodb://localhost:27017

# Import with authentication
./import-to-vm.sh -d ./export/nightscout -t mongodb://nightscout_user:password@localhost:27017

# High-performance import with parallel processing
./import-to-vm.sh -d ./export/nightscout -t mongodb://localhost:27017 --parallel 8 --workers 8

# Import with oplog replay for consistency (if exported with --oplog)
./import-to-vm.sh -d ./export/nightscout -t mongodb://localhost:27017 --oplog

# Drop existing database before import (use with caution)
./import-to-vm.sh -d ./export/nightscout -t mongodb://localhost:27017 --drop
```

### Parameters:
- `-d`: Directory containing exported data
- `-t`: Target MongoDB connection string
- `-n`: Database name (default: nightscout)
- `--drop`: Drop existing database before import (optional)
- `--oplog`: Replay oplog for point-in-time consistency
- `--parallel NUM`: Number of parallel collections to process (default: 4)
- `--workers NUM`: Number of insertion workers per collection (default: 4)

## Step 4: Update Nightscout Configuration

Update your Nightscout environment variables. The format depends on your MongoDB setup:

```bash
# Local MongoDB without authentication
MONGODB_URI=mongodb://localhost:27017/nightscout

# Docker Compose (internal network)
MONGODB_URI=mongodb://mongodb:27017/nightscout

# With authentication (recommended for production)
MONGODB_URI=mongodb://nightscout_user:password@localhost:27017/nightscout

# Replica set configuration
MONGODB_URI=mongodb://user:pass@host1:27017,host2:27017/nightscout?replicaSet=rs0
```

**Important Nightscout Notes:**
- Variable might be called `MONGO_CONNECTION` in older installations
- Only use ONE of: `MONGODB_URI` or `MONGO_CONNECTION`
- Add `dbsize` to your `ENABLE` variable to monitor database size
- Ensure `API_SECRET` is properly configured

## Step 5: Verify Migration

1. Start your Nightscout application
2. Check that historical data is visible
3. Verify that new data can be written
4. Test all Nightscout features

## Troubleshooting

### Common Issues:

1. **mongodump/mongorestore not found**
   - Install MongoDB Database Tools: https://docs.mongodb.com/database-tools/installation/
   - Required for both export and import operations

2. **Atlas connection issues**
   - Ensure connection string uses `mongodb+srv://` format
   - Check username/password contain only letters and numbers
   - Verify network access in Atlas security settings

3. **Connection timeout**
   - Check network connectivity and firewall settings
   - Verify MongoDB is running: `systemctl status mongod`
   - Test connection: `mongo mongodb://localhost:27017/nightscout`

4. **Authentication failed**
   - Verify credentials in connection string
   - Check user permissions and database access
   - Ensure user exists: `db.getUsers()` in mongo shell

5. **Import fails with duplicate key errors**
   - Use `--drop` flag to replace existing data
   - Or manually drop collections before import

6. **Nightscout connection errors**
   - Check MONGODB_URI format matches your setup
   - Verify only one connection variable is set
   - Check Nightscout logs for specific error messages

7. **Performance issues during migration**
   - Use `--parallel` and `--workers` options for large datasets
   - Consider running during low-traffic periods
   - Monitor system resources during import

### Getting Help:
- Check MongoDB logs: `docker logs mongodb-container`
- Test connection: `mongo mongodb://localhost:27017/nightscout`
- Verify data: Use MongoDB Compass or mongo shell

## Security Notes

- **Never commit connection strings to version control**
- Use environment variables for all credentials
- Enable MongoDB authentication in production
- Configure firewall rules to restrict MongoDB access
- Consider enabling SSL/TLS for database connections
- Regularly backup your data after migration
- Monitor database access logs

## Performance Optimization

- Use `--oplog` for exports to ensure data consistency
- Increase `--parallel` and `--workers` for large datasets
- Monitor system resources during migration
- Consider replica sets for high availability
- Regular maintenance: compact databases and rebuild indexes

## Official References

- [Nightscout Documentation](https://nightscout.github.io/)
- [MongoDB Atlas Migration Guide](https://docs.mongodb.com/atlas/import/mongorestore/)
- [MongoDB Database Tools](https://docs.mongodb.com/database-tools/)
- [Nightscout GitHub Issues](https://github.com/nightscout/cgm-remote-monitor/issues) for community support