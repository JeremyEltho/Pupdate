"""Buddy XP and evolution. Pure functions over a buddy dict."""

FORMS = [(0, "sprout"), (100, "strider"), (250, "guardian")]


def form_for(xp):
    form = FORMS[0][1]
    for need, name in FORMS:
        if xp >= need:
            form = name
    return form


def next_form_at(xp):
    for need, _ in FORMS:
        if xp < need:
            return need
    return None


def add_xp(buddy, amount):
    """Returns (buddy, evolved_to or None)."""
    before = form_for(buddy["xp"])
    buddy = dict(buddy, xp=buddy["xp"] + amount)
    after = form_for(buddy["xp"])
    buddy["form"] = after
    return buddy, (after if after != before else None)
