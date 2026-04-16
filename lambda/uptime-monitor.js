'use strict';

/**
 * uptime-monitor
 *
 * Triggered by EventBridge every 5 minutes.
 * PINGs the ALB /check endpoint and publishes to SNS if the app is down.
 *
 * Required env vars (set by Terraform):
 *   ALB_URL       — e.g. http://my-app-alb-975584628.eu-north-1.elb.amazonaws.com
 *   SNS_TOPIC_ARN — e.g. arn:aws:sns:eu-north-1:016605188495:my-app-downtime-alerts
 */

const https = require('https');
const http = require('http');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');

const sns = new SNSClient({ region: process.env.AWS_REGION || 'eu-north-1' });

const ALB_URL = process.env.ALB_URL || 'http://my-app-alb-975584628.eu-north-1.elb.amazonaws.com';
const SNS_TOPIC = process.env.SNS_TOPIC_ARN || 'arn:aws:sns:eu-north-1:016605188495:my-app-downtime-alerts';
const TIMEOUT_MS = 8000;
const CHECK_PATH = '/check';

// ── helpers ──────────────────────────────────────────────────────────────────

function fetchUrl(urlStr) {
    return new Promise((resolve, reject) => {
        const url = new URL(urlStr);
        const client = url.protocol === 'https:' ? https : http;

        const req = client.get(
            { hostname: url.hostname, port: url.port || (url.protocol === 'https:' ? 443 : 80), path: CHECK_PATH, timeout: TIMEOUT_MS },
            (res) => {
                let body = '';
                res.on('data', (chunk) => { body += chunk; });
                res.on('end', () => resolve({ statusCode: res.statusCode, body }));
            }
        );

        req.on('timeout', () => { req.destroy(); reject(new Error(`Request timed out after ${TIMEOUT_MS}ms`)); });
        req.on('error', reject);
    });
}

async function publishAlert(subject, message) {
    const cmd = new PublishCommand({
        TopicArn: SNS_TOPIC,
        Subject: subject,
        Message: message,
    });
    const result = await sns.send(cmd);
    console.log('SNS alert published:', result.MessageId);
    return result;
}

// ── handler ──────────────────────────────────────────────────────────────────

exports.handler = async (event) => {
    const checkUrl = `${ALB_URL}${CHECK_PATH}`;
    const timestamp = new Date().toISOString();

    console.log(`[${timestamp}] Checking: ${checkUrl}`);

    try {
        const { statusCode, body } = await fetchUrl(ALB_URL);

        console.log(`HTTP ${statusCode} — body: ${body.slice(0, 200)}`);

        if (statusCode === 200) {
            console.log('App is UP.');
            return { status: 'ok', statusCode, timestamp };
        }

        // Non-200 — treat as down
        const subject = `[ALERT] my-app is DOWN — HTTP ${statusCode}`;
        const message = [
            `Uptime check FAILED at ${timestamp}`,
            `URL:         ${checkUrl}`,
            `HTTP status: ${statusCode}`,
            `Response:    ${body.slice(0, 500)}`,
            '',
            'Check the ALB target group and EC2 instance health in the AWS console.',
        ].join('\n');

        await publishAlert(subject, message);
        return { status: 'alert_sent', statusCode, timestamp };

    } catch (err) {
        console.error('Check failed with error:', err.message);

        const subject = `[ALERT] my-app health check ERROR`;
        const message = [
            `Uptime check threw an error at ${timestamp}`,
            `URL:   ${checkUrl}`,
            `Error: ${err.message}`,
            '',
            'The app may be unreachable. Check the ALB and EC2 health in the AWS console.',
        ].join('\n');

        await publishAlert(subject, message);
        return { status: 'error', error: err.message, timestamp };
    }
};