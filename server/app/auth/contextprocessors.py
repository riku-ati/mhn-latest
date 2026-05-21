from app.auth import current_user


def user_ctx():
    """
    Inserts current user into templates context.
    """
    return dict(user=current_user)
