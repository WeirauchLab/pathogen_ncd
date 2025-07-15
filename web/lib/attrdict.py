"""
Attribute-accessible dicts (like JavaScript); primarily for use in Jinja
templates

Authors:  Kevin Ernst <kevin.ernst -at- cchmc.org>; Chris Griffith
License:  MIT; under the same terms as cdgriffith/Reusables
"""
import json
from collections.abc import Mapping


# flake8: noqa: E501
class AttrDict(dict):
    """A simple attribute-accessible dict wrapper (like JavaScript objects)

    * tip of the hat to `this blog post`_
    * see also this SO thread: `Accessing dict keys like an attribute?`_"
    * see also `cdgriffith/Box`_, which is what `Dynaconf`_ uses under the hood

    Incorporates code from `cdgriffith/Reusables` (c) 2014-2020 - Chris
    Griffith - MIT License

    .. _cdgriffith/Reusables: https://github.com/cdgriffith/Reusables
    .. _this blog post: https://medium.com/swlh/jdict-javascript-dict-in-python-e7a5383939ab
    .. _Accessing dict keys like an attribute?: https://stackoverflow.com/a/5021467/785213
    .. _cdgriffith/Box: https://github.com/cdgriffith/Box
    .. _Dynaconf: https://github.com/rochacbruno/dynaconf
    """
    _protected_attrs = dir({})

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        for k in self.keys():
            # convert booleans
            if self[k] == 'True':
                self[k] = True
            elif self[k] == 'False':
                self[k] = False
            elif isinstance(self[k], Mapping):
                self[k] = AttrDict(self[k])

    def __getattr__(self, attr):
        try:
            return object.__getattribute__(self, attr)
        except AttributeError:
            # FIXME: when? why? because it's got spaces or funny characters?
            try:
                return self[attr]
            except KeyError:
                raise AttributeError(attr)

    def __setattr__(self, attr, value):
        if attr in self._protected_attrs:
            raise AttributeError(f"Attribute '{attr}' is protected")
        if isinstance(value, dict):
            value = AttrDict(**value)
        try:
            object.__getattribute__(self, attr)
        except AttributeError:
            try:
                self[attr] = value
            # this seems… unnecessary?
            except Exception:
                raise AttributeError(key)
        else:
            object.__setattr__(self, attr, value)

    def to_dict(self):
        """Convenience function to return the whole structure as a dict"""
        return dict(self)


class JSONAttrDictEncoder(json.JSONEncoder):
    """
    A JSON serializer for :class:`AttrDict`s.

    See :class:``py3:json.JSONEncoder`` in the standard library for details.
    """
    def default(self, o):
        if isinstance(o, AttrDict):
            return dict(o)
        return json.JSONEncoder.default(self, o)
