# Julia-visualization

## plotOSM()

Downloads an image from Open Street Map (OSM) and plots an existing line/scatter-plot on top of the image.

Example of plotting the position of six capitals in Europe:

```julia
using("plotOSM.jl")
tempPath = raw"PATH_TO_DIR\temp.png" # Temporary path for saving image, can be removed by rm(tempPath)
lat = [48.8708,   51.5188,   41.9260,   40.4312,   52.523,  37.982]
lon = [2.4131,    -0.1300,    12.4951,   -3.6788,    13.415,   23.715]
p = scatter(lon,lat,color=:blue,label="cities")
plotOSM(p,tempPath)
title!("Six capitals in Europe")
```

![OSM_cities](https://user-images.githubusercontent.com/37980849/97043450-ca55ae80-1572-11eb-8ab6-1e174b38d0cb.png)
