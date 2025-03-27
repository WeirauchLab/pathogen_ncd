#!/opt/rh/rh-python36/root/usr/bin/python3
import os
import sys
import cgi
import sqlite3
import json

if os.getenv('RESULTS_API_ENVIRON') == 'dev':
    # tracebacks in the browser... in GLORIOUS lavender and magenta!
    # source: https://docs.python.org/3.8/library/cgi.html
    import cgitb; cgitb.enable()
    # send the headers now, in case anything generates a traceback
    print("Content-Type: text/html\n")

try:
    MYPATH = os.path.abspath(os.path.dirname(__file__))
except NameError:
    MYPATH = 'api'

DATABASE_FILE    = MYPATH + '/../data/results.sqlite3'
TABLE            = 'results'
RECS_PER_REQUEST = 10


try:
    sys.path.append(MYPATH + "/venv/lib/python{}.{}/site-packages"
            .format(sys.version_info.major, sys.version_info.minor))
    from jinja2 import Template
except ImportError:
    print("Status: 500 Internal Server Error")
    print("Internal Server Error")

onerecord = Template("""Content-Type: text/html

<table id="detail-{{ id }}" cellpadding="5" cellspacing="0" border="0"
       style="padding-left:50px;">
  <tr>
    {% for value in record %}<td>{{ value }}</td>{% endfor %}
  </tr>
</table>
""")

usage = Template("""Content-Type: text/html

<html>
  <p>
    <strong>Usage</strong>: <code>?id=<strong>ID</strong></code>
  </p>
</html>
""")

conn = sqlite3.connect(DATABASE_FILE) # >=3.4 --> ?mode=ro', uri=True
form = cgi.FieldStorage()

try:
    recid = int(form.getfirst('id'))
except TypeError:
    print(usage.render())
    sys.exit()

# just so I know how to do it
#cur = conn.execute("PRAGMA table_info(%s)" % TABLE)
#tableinfo = cur.fetchall()
#columns = [x[1].lower() for x in tableinfo]  # column name is 2nd element

cur = conn.execute(
    "SELECT rowid, * FROM %s WHERE rowid = ?" % TABLE, (recid,)
)

record = cur.fetchone()
print(onerecord.render(id=recid, record=record))
cur.close()
conn.close()
