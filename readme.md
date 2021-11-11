# Scripts for AIS encounter / shipdomain analysis

## Intro

This repository hosts the scripts that have been used to carry out the analysis of ship domain / ship encounters based on AIS data.


## How to run?

The workflow is described in the Unix Makefile.
The database and host parameters need to be set in the Makefile.

It expects a Postgres installation, where PostGIS is enabled (and has certain tablespaces configured).
Moreover, connection information was stored inside .pgpass.


## More details

The work has been described in the following paper: <http://www.gdmc.nl/publications/2021/Ship_Domain_Variations_Strait_of_Istanbul.pdf>.

```
@inproceedings{AltanMeijers2021,
  author = {Yigit Can Altan and Martijn Meijers},
  title = {Ship Domain Variations in the Strait of Istanbul},
  pages = {14},
  booktitle = {Proceedings of 'Siga2 Maritime and Ports, The Port and Maritime Sector: Key Developments and Challenges, 5-7 May 2021'},
  month = {May},
  year = {2021},
  address = {Antwerp, on-line},
  url = {https://www.uantwerpen.be/en/conferences/siga2-2021-conferenc/},
  pdf = {http://www.gdmc.nl/publications/2021/Ship_Domain_Variations_Strait_of_Istanbul.pdf}
}
```


## License

MIT license. (c) 2020-2021 Martijn Meijers, Delft University of Technology.
