import numpy as np

ts = np.arange(0,256)
xs = ts/256.0 * 2*np.pi

ys = np.round(np.sin(xs)*127.5-0.5)

myfile = open("sinedata.txt","w")

for i in ys:
    j = int(i)
    if j<0:
        j += 256
    myfile.write("    .byte {}\n".format(j))

myfile.close()