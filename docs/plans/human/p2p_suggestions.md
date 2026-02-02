# New logger command: P2P

**Status: DONE**

`P2P` is a new command to add to the logger palette. It should only work on POTA activations. It should filter available POTA spots and then find spotters close to your grid square. Then, it should call VailRBN filtering spots by that list of spotters (https://vailrerbn.com/docs/endpoints#spots), and then find any callsigns that show up in those spots. Then, show them in a list sorted by spot age and SNR. Color code for ease of consumption. It should have the same behavior on click as the POTA spots.
