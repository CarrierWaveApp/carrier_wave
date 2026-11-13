# Sync improvements

**✅ DONE**

We need to improve a few things about Ham2K LoFi, QRZ, and POTA.

First, users must ensure they have download enabled on Ham2K LoFi. Currently the only way to do that is by chatting with Sebastian KI2D on his Discord server (https://discord.gg/K29T3Njh4U). If you try to download and get 0 items from LoFi, they likely don't have download enabled.

Second, I'm getting reports of partial downloads from both QRZ and LoFi. I have one report of someone that has ~14k QSOs on QRZ but we're only downloading 2,000. Similarly, it's only downloading a partial set of that user's LoFi QSOs. We MUST ensure that we download every QSO available.

Third, I'm getting timeouts on POTA.app downloads. Some users have really high numbers of jobs (477 in one case). We should batch the jobs/activations and their QSOs so that we can do partial downloads and then continue. We shouldn't try downloading all jobs and then all activations and then all QSOs.
