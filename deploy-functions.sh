#!/bin/bash
# Deploy Firebase Functions
# firebase login  (first time)
# IAM issues: functions/FUNCTIONS_DEPLOY_IAM.md

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/functions"
npm install
cd "$ROOT"
firebase deploy --only functions
