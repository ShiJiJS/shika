import json
import logging
import time

class PathOnlyFormatter(logging.Formatter):
    def format(self, record):
        if not isinstance(record.args, tuple) or len(record.args) != 5:
            return json.dumps({"unsupported_record": True})
        _, method, full_path, _, status = record.args
        return json.dumps({"time": time.time(), "method": method, "path": str(full_path).split("?", 1)[0], "query": str(full_path).partition("?")[2], "status": int(status)})
