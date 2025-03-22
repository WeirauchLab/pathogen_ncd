"""
Facilitates printing ANSI colors on Unix consoles. Use Colorama on Windows.

Source: https://gist.github.com/4007035
"""
import subprocess


class AnsiColors(object):
    """
    Provides ANSI terminal color codes which are gathered via the ``tput``
    utility. That way, they are portable. If there occurs any error with
    ``tput``, all codes are initialized as an empty string.
    The provides fields are listed below.

    Control:
      - bold
      - underline
      - reset

    Colors:
      - red
      - green
      - yellow
      - blue
      - magenta
      - cyan
      - white

    :license: MIT
    """
    def __init__(self):

        sco = subprocess.check_output

        try:
            self.bold = sco("tput bold".split()).decode('utf-8')
            self.ul = sco("tput sgr 0 1".split()).decode('utf-8')
            self.reset = sco("tput sgr0".split()).decode('utf-8')

            self.red = sco("tput setaf 1".split()).decode('utf-8')
            self.green = sco("tput setaf 2".split()).decode('utf-8')
            self.yellow = sco("tput setaf 3".split()).decode('utf-8')
            self.blue = sco("tput setaf 4".split()).decode('utf-8')
            self.magenta = sco("tput setaf 5".split()).decode('utf-8')
            self.cyan = sco("tput setaf 6".split()).decode('utf-8')
            self.white = sco("tput setaf 7".split()).decode('utf-8')

        # problems on Unix will yield a subprocess.CalledProcessError
        # on Windows, a FileNotFoundError; just ignore in both cases
        except:
            self.bold = ""
            self.ul = ""
            self.reset = ""

            self.red = ""
            self.green = ""
            self.yellow = ""
            self.blue = ""
            self.magenta = ""
            self.cyan = ""
            self.white = ""
