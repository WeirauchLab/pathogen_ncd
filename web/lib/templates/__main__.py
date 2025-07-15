"""
Author:   Kevin Ernst <kevin.ernst -at- cchmc.org>
License:  GPL; see LICENSE.txt in the top-level directory

© 2025 Cincinnati Children's Hospital Medical Center and the author(s)
"""
import sys
from . import process_templates

process_templates(sys.argv[1:])
