"""The trailer's clock, shared by the score (music.py) and the edit (edit.py).

Everything sits on a 100 BPM grid of 4/4 bars (2.4 s each), so cuts land on
the music. bar(b, beat) gives the time in seconds.
"""
BPM = 100
BEAT = 60.0 / BPM
BAR = 4 * BEAT


def bar(b, beat=0.0):
    return b * BAR + beat * BEAT


# sections (bars)
PROLOGUE = 0      # the Bell, the crack, the grey
CRACK = 4         # the Bell cracks on this downbeat (9.6 s)
DARK = 4.25       # the grey section after the crack
GUILD = 10        # the tavern, the nations (24.0 s)
GUILD_FULL = 12   # the tavern full of life: the band comes in
FACTIONS = 16     # the four factions and their answers to the Hush (38.4 s)
BOARD = 22        # the quest board
BREAK = 23        # "Write yours." over a riser
BATTLE = 24       # the drop (57.6 s)
DEATH = 31        # a member falls: the music stops dead (74.4 s)
FINAL = 32.5      # the Unnamed (78.0 s)
BUILD = 37.5      # the last build before the title
TITLE = 38.5      # the hit and the title (92.4 s)
END = 42.0        # the last frame (100.8 s)

LENGTH = bar(END)
