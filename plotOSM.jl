using Plots, HTTP, LinearAlgebra, Statistics, Geodesy, Images, FileIO, Colors, CoordinateTransformations, OffsetArrays, Rotations
gr()

"""
Adds an OSM-image beneath an existing plot. Rescales axes, so all plotting
should be done before calling plotOSM()

Currently supports simple scatter and line plots.
Should be executed in the following order:
    Plot lines and points -> run plotOSM() -> set title

# Usage example:
    tempPath = raw"PATH_TO_DIR\temp.png"      # Where to save temporary file
                                              # Can be removed after plotting
                                              # by running rm(tempPath)

    lat = [48.8708,   51.5188,   41.9260,   40.4312,   52.523,  37.982]
    lon = [2.4131,    -0.1300,    12.4951,   -3.6788,    13.415,   23.715]
    p = scatter(lon,lat,color=:blue,label="cities")

    plotOSM(p,tempPath)
    title!("Six capitals in Europe")
"""

function plotOSM(plotvar,tempPath)
    scale = 2   # Increases resolution of image
    height = 640
    width = 640
    tileSize = 256
    xlim = [xlims(plotvar)[1],xlims(plotvar)[2]]
    ylim = [ylims(plotvar)[1],ylims(plotvar)[2]]
    lat = (ylim[2]+ylim[1])/2
    lon = (xlim[2]+xlim[1])/2

    # Find zoom level for image
    xExtent,yExtent = latLonToMeters(ylim, xlim)
    minResX = diff(xExtent)/width
    minResY = diff(yExtent)/height
    minRes = maximum([minResY[1], minResX[1]])
    initialResolution = 2.0*pi*6378137/tileSize
    zoomlevel = floor(Int,log2(initialResolution/minRes))

    # Enforce valid zoom-level
    if zoomlevel<0
        zoomlevel = 0
    end
    if zoomlevel>19
        zoomlevel = 19
    end

    # Download image
    preamble = raw"http://tyler-demo.herokuapp.com/?"
    latitude = "lat=$lat"
    longitude = "&lon=$lon"
    zoomStr = "&zoom=$zoomlevel"
    sizeStr = string("&width=$width&height=$height")

    url = string(preamble,latitude, longitude, zoomStr, sizeStr)
    #http://tyler-demo.herokuapp.com/?lat=51.5008198&lon=-0.1427437&width=800&height=600
    HTTP.download(url,tempPath)

    img = load(tempPath)
    img = RGB.(img)
    img = parent(img)
    h,w = size(img)

    # Find limits and axes on plot
    curResolution = initialResolution/(2^zoomlevel) # meters/pixel (EPSG:900913)
    center = [lat,lon]
    xlim,ylim = getCorners(center, zoomlevel, w, h,curResolution)
    limits = [xlim,ylim]
    ytick = round.(reverse(collect(range(xlim[1],stop=xlim[2],length=10))),digits=5)
    xtick = round.(collect(range(ylim[1],stop=ylim[2],length=10)),digits=5)

    # Crop, scale and plot image
    cropim = getIm(center, zoomlevel, w, h,curResolution,img)
    p = plot(cropim)

    # Find limits of new plot
    ymin = limits[1][1]
    xmin = limits[2][1]
    dy = limits[1][2]-limits[1][1]
    dx = limits[2][2]-limits[2][1]

    # Redo all plotting with scaled values
    plotdata = plotvar.series_list
    for i in 1:length(plotdata)
        x = plotdata[i].plotattributes[:x]
        y = plotdata[i].plotattributes[:y]
        seriestype = plotdata[i].plotattributes[:seriestype]
        lbl = plotdata[i].plotattributes[:label]
        xplot,yplot = scaleCoords([x,y],xmin,ymin,dx,dy,h,w)
        if seriestype==:path
            linecolor = plotdata[i].plotattributes[:linecolor]
            linewidth = plotdata[i].plotattributes[:linewidth]
            p = plot!(xplot,yplot,color=linecolor,linewidth=linewidth,label=lbl)
        elseif seriestype==:scatter
            seriescolor = plotdata[i].plotattributes[:seriescolor]
            mshape = plotdata[i].plotattributes[:markershape]
            msize = plotdata[i].plotattributes[:markersize]
            p = scatter!(xplot,yplot,color=seriescolor,markershape=mshape,
                        label=lbl,markersize=msize)
        end
    end
    return plot(p,xticks=xticks=(0:w/5:w, ["$i" for i in xtick]),
            yticks=(0:h/5:h, ["$i" for i in ytick]))
end

# Converts given lat/lon in WGS84 Datum to XY in Spherical Mercator EPSG:900913"
function latLonToMeters(lat, lon)
    originShift = 2*pi*6378137/2.0
    x = lon.*(originShift/180)
    y = log.(tan.((lat.+90).*(pi/360)))./(pi/180)
    y = y.*(originShift/180)
    return (x,y)
end

function metersToLatLon(x,y)
    # Converts XY point from Spherical Mercator EPSG:900913 to lat/lon in WGS84 Datum
    originShift = 2*pi*6378137/2.0 # 20037508.342789244
    lon = (x./originShift).*180
    lat = (y./originShift).*180
    lat = (180/pi).*((atan.(exp.(lat.*(pi/180))).*2).-(pi/2))
    return (lat,lon)
end

# Get coordinates of image corners
function getCorners(center, zoom, mapWidth, mapHeight,curResolution)
    centerPixelY = round(mapHeight/2)
    centerPixelX = round(mapWidth/2)
    centerX,centerY = latLonToMeters(center[1],center[2]) # center coordinates in EPSG:900913
    xVec = centerX.+(([1,mapWidth].-centerPixelX).*curResolution) # x vector
    yVec = centerY.+(([1,mapHeight].-centerPixelY).*curResolution) # y vector
    xlim,ylim = metersToLatLon(xVec,yVec)
    return (xlim, ylim)
end

# Find the correct cropping and scaling of image
function getIm(center, zoom, mapWidth, mapHeight,curResolution,imag)
    centerX,centerY = latLonToMeters(center[1],center[2])
    centerPixelY = round(Int,mapHeight/2)
    centerPixelX = round(Int,mapWidth/2)
    xVec = ((collect(1:mapWidth).-centerPixelX).*curResolution).+centerX
    yVec = ((collect(mapHeight:-1:1).-centerPixelY).*curResolution).+centerY
    xMesh,yMesh = meshgrid(xVec,yVec)

    latMesh,lonMesh = metersToLatLon(xMesh,yMesh)

    latVect = collect(range(latMesh[1,1],stop=latMesh[end,1],length=mapHeight))
    lonVect = collect(range(lonMesh[1,1],stop=lonMesh[1,end],length=mapWidth))
    uniLonMesh,uniLatMesh = meshgrid(lonVect,latVect)
    uniImag = zeros(mapHeight,mapWidth,2)
    uniImag = myTurboInterp2(lonMesh,latMesh,imag,uniLonMesh,uniLatMesh)
    return uniImag
end

# Image interpolation to fit coordinates
function myTurboInterp2(X,Y,Z,XI,YI)
    XI = XI[1,:]
    X = X[1,:]
    YI = YI[:,1]
    Y = Y[:,1]

    xiPos = NaN*ones(size(XI))
    xLen = size(X)[1]
    yiPos = NaN*ones(size(YI))
    yLen = size(Y)[1]
    # find x conversion
    xPos = 1
    for idx in 1:length(xiPos)
        if XI[idx] >= X[1] && XI[idx] <= X[end]
            while xPos < xLen && X[xPos+1]<XI[idx]
                xPos = xPos + 1
            end
            diffs = abs.(X[xPos:xPos+1].-XI[idx])
            if diffs[1] < diffs[2]
                xiPos[idx] = xPos
            else
                xiPos[idx] = xPos + 1
            end
        end
    end
    # find y conversion
    yPos = 1
    for idx in 1:length(yiPos)
        if YI[idx] <= Y[1] && YI[idx] >= Y[end]
            while yPos < yLen && Y[yPos+1]>YI[idx]
                yPos = yPos + 1
            end
            diffs = abs.(Y[yPos:yPos+1].-YI[idx])
            if diffs[1] < diffs[2]
                yiPos[idx] = yPos
            else
                yiPos[idx] = yPos + 1
            end
        end
    end
    ZI = Z[round.(Int,yiPos),round.(Int,xiPos)]
    return ZI
end

function meshgrid(x,y)
    X = transpose([i for i in x, j in 1:length(y)])
    Y = transpose([j for i in 1:length(x), j in y])
    return (X, Y)
end

function scaleCoords(points,xmin,ymin,dx,dy,height,width)
    xcoord = (points[1].-xmin).*(width/dx)
    ycoord = height.-((points[2].-ymin).*(height/dy))
    return (xcoord,ycoord)
end
