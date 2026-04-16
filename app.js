const express = require('express');
const os = require('os');
const app = express();
const PORT = process.env.PORT || 3000;
const START_TIME = Date.now();

app.use(express.static('public'));

app.get('/check', (req, res) => {
    res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/api/status', (req, res) => {
    const uptime = Math.floor((Date.now() - START_TIME) / 1000);
    res.json({
        services: [
            { name: 'API Server', status: 'operational' },
            { name: 'Database', status: 'operational' },
            { name: 'Cache', status: 'operational' },
            { name: 'Jenkins CI/CD', status: 'operational' },
            { name: 'Docker Registry', status: 'operational' },
            { name: 'Load Balancer', status: 'operational' },
            { name: 'Auto Scaling', status: 'operational' },
            { name: 'CloudWatch', status: 'operational' },
        ],
        system: {
            uptime_seconds: uptime,
            uptime_human: formatUptime(uptime),
            hostname: os.hostname(),
            platform: os.platform(),
            memory_used_mb: Math.round((os.totalmem() - os.freemem()) / 1024 / 1024),
            memory_total_mb: Math.round(os.totalmem() / 1024 / 1024),
            cpu_cores: os.cpus().length,
            node_version: process.version,
            environment: process.env.NODE_ENV || 'development',
        },
        meta: {
            version: '1.0.0',
            deployed_at: new Date().toISOString(),
            region: 'eu-north-1',
        }
    });
});

function formatUptime(seconds) {
    const d = Math.floor(seconds / 86400);
    const h = Math.floor((seconds % 86400) / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    return `${d}d ${h}h ${m}m ${s}s`;
}

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});

module.exports = app;