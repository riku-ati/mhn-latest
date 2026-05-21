#!/usr/bin/env python3

# Expose the Flask app as 'app' so gunicorn can find it via "mhn:app"
from app import mhn as app

if __name__ == '__main__':
    app.run(debug=False, host='0.0.0.0', port=8000)
