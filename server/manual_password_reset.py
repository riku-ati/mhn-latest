#!/usr/bin/env python3
from flask_security.utils import hash_password
from app.auth.models import User
from app import mhn, db
import sys
from getpass import getpass

with mhn.test_request_context():
    email = input("Enter email address: ").strip()

    password = getpass("Enter new password: ")
    password2 = getpass("Enter new password (again): ")

    if password != password2:
        print("Passwords didn't match, try again")
        sys.exit(1)

    user = User.query.filter_by(email=email).first()
    if user:
        print("user found, updating password")
        user.password = hash_password(password)
        db.session.add(user)
        db.session.commit()
    else:
        print("No user with that email address was found.")
