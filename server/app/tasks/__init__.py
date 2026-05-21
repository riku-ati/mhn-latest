from celery import Celery

from app import mhn


celery = Celery(include=['app.tasks.rules'])
celery.conf.update(mhn.config)
TaskBase = celery.Task


class ContextTask(TaskBase):
    abstract = True

    def __call__(self, *args, **kwargs):
        with mhn.app_context():
            return TaskBase.__call__(self, *args, **kwargs)


celery.Task = ContextTask
