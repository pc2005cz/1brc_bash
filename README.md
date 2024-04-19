# 1️⃣🐝🏎️ The One Billion Row Challenge

- Challenge blog post: https://www.morling.dev/blog/one-billion-row-challenge/
- Challenge repository: https://github.com/gunnarmorling/1brc

The challenge: **compute simple floating-point math over 1 billion rows. As fast as possible, without dependencies.**

The spoiler: **this is gonna be slow**

Compatible with a vanilla or a recompiled bash with the support of multiple coprocesses. No coreutils nor busybox commands are used. If you want to use bash without working coprocesses, you need to use `mkfifo` command to create named pipes for the communication with multiple workers running as the background processes.

This script was developed and tested on Slackware-current's bash version `5.2.26(1)-release` and on a recompiled one from git commit `f3b6bd19457e260b65d11f2712ec3da56cef463f`. The used machine is AMD Ryzen 5 3600 @ 3600MHz with 2x 8GB RAM @ 3200MHz.

## Running the challenge

You need a bash interpreter. Bash compatible interpreters (dash) were untested. Busybox ash is also not supported (the script is using coprocesses, arrays and regular expressions in `[[`).

You gonna need bash version 5.0 which supports coprocesses (`coproc` keyword). The current version prints an `execute_coproc` warning as the coprocesses are still an experimental feature, but the current version of the script the multiple coprocesses are working fine (I think there was a problem with older bash forgetting previously started coprocess or something).

If you want to remove the error message you can recompile your bash and change the file `bash/config-top.h` to have `MULTIPLE_COPROCS` macro set to `1`. You can also try to compile with CFLAGS optimizations for a faster execution.

### Create the measurements file with 1B rows

I've used (a C version of 1brc)[https://github.com/dannyvankooten/1brc] to generate the initial 1G row file. It is recommended to create just 10M row file and maybe even less when debugging the code.

From compiled C version, run:
```
bin/create-sample 1000000000
```

### Start the script

The script has 1 required and 1 optional argument. The required argument is the pathname of the input file (`measurements.txt`). The optional argument is the number of workers. If there is none worker count specified, only 1 worker will be used (to be compatible with older bash versions).

```
time ./bash_1brc.sh path/to/measurements.txt 4
```

In the example, there will be 1 central process which will distribute every N-th input line to each of N workers.

Increasing the number of workers will speed up the computation up to the certain point. There is a sweet spot between the central process being underused or saturated.

The script will generate a file `sorted_1713514253_1713514513.txt` in the `results` subdirectory where the script was started. If there is no `results` subdirectory, it will just store the result in the same directory. The first number in the filename (seconds since the epoch) is generated right at the start of the script and the second number is generated right before the final sort. Start the script with `time` if you want to know the exact running time. The differences will be less than 1 promile though.

### Results

On the machine (AMD Ryzen 5 3600 @ 3600MHz with 2x 8GB RAM @ 3200MHz), which was used to create the initial 1brc implementation in bash, the entire 1G rows took between 5 and 6 hours. The used number of workers was 4. With the last changes in the code it should run faster with 5.

Following results for 1G were run before the final sorting was implemented:

```
real	338m12,274s
user	219m31,485s
sys	    85m49,691s
```

```
real	348m41,391s
user	228m21,530s
sys	    87m1,022s
```

After implementing insertion sort the script was run again with these results:

```
real	342m35,498s
user	223m33,945s
sys 	85m42,287s
```

The last version of the script was used for measurement of the impact of different number of workers. Only 10M rows were used:

| Workers | 1st result (m:s.ms) | 2nd result (m:s.ms) | 3rd result (m:s.ms) |
|:-------:|--------------------:|--------------------:|--------------------:|
|    1    |           12:20.304 |           12:23.797 |           12:13.547 |
|    2    |            6:10.527 |            6:12.966 |            6:11.379 |
|    3    |            4:19.865 |            4:23.600 |            4:19.154 |
|    4    |            3:30.620 |            3:33.008 |            3:09.340 |
|    5    |            2:39.601 |            2:37.792 |            2:39.559 |
|    6    |            2:41.892 |            2:41.190 |            2:41.549 |
|    7    |            2:52.517 |            2:54.027 |            2:53.291 |
|    8    |            3:23.429 |            3:25.387 |            3:23.122 |
|    9    |            3:25.087 |            3:29.683 |            3:34.031 |
