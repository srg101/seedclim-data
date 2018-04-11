####################
#todo############
#check species in taxon table before inserting
#merge subturf taxa
####################

#for loop
import.data<-function(filelist, con){
  require(dplyr)
  require(readr)
  sapply(filelist,function(n){
    #browser()
  
                                                                              #uncomment to loop
    #n <- "/Users/fja062/Documents/seedclimComm/seedclimComm/rawdata/Alrust2011.sp.fix.vv.csv"                  #comment to loop
    print(n)
    chkft <- c("pleuro","acro", "liver", "lichen", "litter" ,"soil", "rock", "totalVascular", "totalBryophytes", "totalLichen", "vegetationHeight", "mossHeight")
    es_MX <- locale("es", decimal_mark = ",", encoding = "Windows-1252")
    dat <- read.csv2(n, dec = ",", stringsAsFactors = FALSE)
    if(ncol(dat) > 1){
      if(any(sapply(dat[, chkft], class) == "character")) 
        es_MX <- locale("es", decimal_mark = ".", encoding = "Windows-1252")
        dat <- read.csv2(n, dec = ".", stringsAsFactors = FALSE)  
    }else{
      es_MX <- locale("es", decimal_mark = ".", encoding = "Windows-1252")
      dat <- read.csv(n, dec = ".", stringsAsFactors = FALSE)
     }
         
    dat <- dat[!is.na(dat$originPlotID),]
    names(dat) <- make.names(names(dat))
    dat$turfID <- trimws(dat$turfID)
    head(dat)
    names(dat)
    if(class(dat$comment) == "character"){
      try(Encoding(dat$comment) <- "latin1")
    }
    
    
    #remove numeric suffix on duplicates
    names(dat) <- gsub("_\\d$", "", names(dat))

        #extract turf data
    turf <- dat[,c("turfID", "TTtreat", "RTtreat", "GRtreat", "originPlotID", "destinationPlotID")]
    turf <- unique(turf)
    turf$TTtreat <- trimws(turf$TTtreat) #  trim white spaces
    turf$RTtreat <- trimws(turf$RTtreat)
    turf$GRtreat <- trimws(turf$GRtreat)
  
    turf
    names(turf)
    
    alreadyIn <- dbGetQuery(con,"select turfId from turfs")$turfId
    newTurfs <- turf[!as.character(turf$turfID) %in% alreadyIn,] #find which turfs IDs are not already in database
    
    if(nrow(newTurfs) > 0) dbWriteTable(con, "turfs", newTurfs, row.names = FALSE, append = TRUE)
    nrow(turf)
    nrow(newTurfs)
    
    message("done turfs")                                  
    
    
    #subTurf env
    subturfEnv <- dat[dat$Measure != "Cover", c("turfID", "subPlot", "year", "pleuro", "acro", "liver", "lichen", "litter", "soil", "rock", "comment")]
    names(subturfEnv)[2] <- "subTurf"
    if(!is.null(dat$missing)){
       bad = dat$missing[dat$Measure != "Cover"]
       bad[is.na(bad)] <- ""
      subturfEnv <- cbind(subturfEnv, bad = bad)
    } else{
      subturfEnv <- cbind(subturfEnv, bad = "")    
    }
    subturfEnv 
    dbWriteTable(con, "subTurfEnvironment", subturfEnv, row.names = FALSE, append = TRUE)
    nrow(subturfEnv)
    
    #TurfEnv
    turfEnv <- dat[dat$Measure == "Cover", c("turfID","year",  "pleuro", "acro", "liver", "lichen", "litter", "soil", "rock", "totalVascular","totalBryophytes", "totalLichen", "vegetationHeight", "mossHeight", "comment","recorder", "date")]
    # if(any(nchar(as.character(turfEnv$comment[!is.na(turfEnv$comment)])) > 255)) {
    #   stop ("more than 255 characters in a comment field in turfEnv")
    # }
   dbWriteTable(con, "turfEnvironment", turfEnv, row.names = FALSE, append = TRUE)
  nrow(turfEnv)   
  
  #Mergedictionary
  mergedictionary <- dbGetQuery(con,"SELECT * FROM mergedictionary")  
  
    #TurfCommunity  
  
  spp <- cbind(dat[, c("turfID", "year")], dat[, (which(names(dat) == "recorder") + 1) : (which(names (dat) == "pleuro")-1) ])[dat$Measure == "Cover",]
  spp[, 3 : ncol(spp)] <- plyr::colwise(as.numeric)(spp[, 3 : ncol(spp)])
  notInMerged <- setdiff(names(spp)[-(1:2)], mergedictionary$oldID)
  mergedictionary <- rbind(mergedictionary, cbind(oldID = notInMerged, newID = notInMerged))
  mergedNames <- plyr::mapvalues(names(spp)[-(1:2)], from = mergedictionary$oldID, to = mergedictionary$newID, warn_missing = FALSE)
  sppX <- lapply(unique(mergedNames), function(n){
    rowSums(spp[, names(spp) == n, drop = FALSE])
    })
  sppX <- setNames(as.data.frame(sppX), unique(mergedNames))
  spp <- cbind(spp[, 1:2], sppX)

  table(as.vector(sapply(spp[, -(1:2)], as.character)), useNA = "ifany") #oddity search 

  spplist <- unique(dbGetQuery(con,"SELECT newID FROM mergedictionary")$newID)
  
  newspp <- setdiff(names(spp)[-(1:2)], spplist)
  if(length(newspp)>0){
    write.csv(data.frame(filename = n, species = newspp), file = "newspecies_log.csv", append = TRUE)
    #stop("new taxa found: ", paste(newspp, collapse = " "))
  }
  
  sppT <- plyr::ldply(3:ncol(spp), function(nc){
      sp <- spp[, nc]
      cf <- grep("cf", sp, ignore.case = TRUE)
      sp <- gsub("cf", "", sp, ignore.case = TRUE)
      sp <- gsub("\\*", "", sp, ignore.case = TRUE)
      spp2 <- data.frame(turfID = spp$turfID, year = spp$year, species = names(spp)[nc], cover = as.numeric(sp), cf = 0)
      spp2$cf[cf] <- 1
      spp2 <- spp2[!is.na(spp2$cover), ]
      spp2 <- spp2[spp2$cover > 0, ]
      spp2
    })
  #initial number of rows in turfCommunity
  initTC <- dbGetQuery(con, "select count(*) as n from turfCommunity")$n
  dbWriteTable(con, "turfCommunity", sppT, row.names=FALSE, append = TRUE)
  postTC <- dbGetQuery(con, "select count(*) as n from turfCommunity")$n
  stopifnot(nrow(sppT) == postTC - initTC)
     #Check rows query for TurfCommunity :
  
                                              
     #subTurfCommunity  
     message("subturfcommunity")  
    subspp <- cbind(dat[, c("turfID", "year", "subPlot")], dat[, (which(names(dat) == "recorder") + 1) : (which(names(dat) == "pleuro") -1) ])[dat$Measure != "Cover",]
    subspp[subspp == 0] <- NA
    subsppX <- lapply(unique(mergedNames), function(sppname){
      species <- subspp[, names(subspp) == sppname, drop = FALSE]
      if (ncol(species) == 1) {
        return(species)
      } else {
        apply (species, 1, function(r) {
          occurence <- which(!is.na(r))
          if(length(occurence) == 0) return(NA)
          if(length(occurence) == 1) return(r[occurence])
          else {
            warning(paste("more than one species observation in same subplot!"))
            write.csv(data.frame(filename = n, species = sppname, occurence = r[occurence]), file = "cooccurence_log.csv", append = TRUE)
            return(r[occurence][1])
          }
        })
      }
    })
    
    
    subsppX <- setNames(as.data.frame(subsppX), unique(mergedNames))
    subspp <- cbind(subspp[, 1:3], subsppX)
    unique(as.vector(sapply(subspp[, -(1:3)], as.character))) #oddity search
    print(table(as.vector(sapply(subspp[, -(1:3)], as.character)))) #oddity search
    
    
    #Find oddities in dataset:
    tmp <- sapply(subspp, function(z){a <- which(z == "f"); if(length(a) > 0){subspp[a, 1:3]} else NULL})
    tmp[!sapply(tmp, is.null)]

    spp0 <- plyr::ldply(as.list(4:ncol(subspp)), function(nc){
      sp <- subspp[,nc ]
      spp2 <- data.frame(turfID = subspp$turfID, year = subspp$year, subTurf = subspp$subPlot, species = names(subspp)[nc], seedlings = 0, juvenile = 0, adult = 0, fertile = 0, vegetative = 0, dominant = 0, cf = 0)
      spp2$cf[grep("cf",sp, ignore.case = TRUE)] <- 1
      spp2$fertile[grep("F",sp, ignore.case = FALSE)] <- 1
      spp2$dominant[grep("D",sp, ignore.case = TRUE)] <- 1       
      spp2$vegetative[grep("V",sp, ignore.case = TRUE)] <- 1
      spp2$seedlings[grep("S",sp, ignore.case = TRUE)] <- 1
      for(i in 2:50){
        spp2$seedlings[grep(paste("Sx",i,sep=""), sp, ignore.case = TRUE)] <- i
        spp2$seedlings[grep(paste(i,"xS",sep=""), sp, ignore.case = TRUE)] <- i
      }    
      spp2$juvenile[grep("J", sp, ignore.case = TRUE)] <- 1
      for(i in 2:50){
        spp2$juvenile[grep(paste("Jx", i, sep = ""),sp, ignore.case = TRUE)] <- i
         spp2$juvenile[grep(paste("xJ", i, sep = ""),sp, ignore.case = TRUE)] <- i
      }
      spp2$adult[unique(c(grep("1", sp, ignore.case = TRUE), grep("F", sp, ignore.case = FALSE), grep("V", sp, ignore.case = TRUE), grep("D", sp, ignore.case = TRUE))) ] <- 1
      spp2<-spp2[rowSums(spp2[,-(1:4)])>0,] #keep only rows with presences
      spp2
    })  
    
    
    #euphrasia rule adults=adults+juvenile+seedling, j=j+s, s=s
    seedlingSp <- c("Euph.fri", "Eup.fri","Eup.sp","Eup.str","Euph.fri","Euph.sp", "Euph.str","Euph.str.1", "Euph.wet", "Poa.ann","Thlaspi..arv","Com.ten","Gen.ten", "Rhi.min", "Cap.bur", "Mel.pra","Mel.sp","Mel.syl","Noc.cae","Ste.med","Thl.arv","Ver.arv")
    #########more annuals?
    
    tmpSp <- spp0[spp0$species %in% seedlingSp,]
      tmpSp$juvenile[tmpSp$juvenile == 0 & tmpSp$adult == 1] <- 1  
      tmpSp$seedlings[tmpSp$seedlings == 0 & tmpSp$adult == 1] <- 1
      tmpSp$seedlings[tmpSp$seedlings == 0 & tmpSp$juvenile == 1] <- 1
    spp0[spp0$species %in% seedlingSp,] <- tmpSp
    
    #check whether rows added successfully
    initSTC <- dbGetQuery(con, "select count(*) as n from subTurfCommunity")$n
    dbWriteTable(con, "subTurfCommunity", spp0, row.names = FALSE, append = TRUE)
    postSTC <- dbGetQuery(con, "select count(*) as n from subTurfCommunity")$n
    stopifnot(nrow(spp0) == postSTC - initSTC)
  
    
    
  ############### Vigdis seedling problem #only for 2011 data     #############################
  if(dat$year[1] == 2011 & FALSE){ #disable seedling error <---- FIX THIS!!!
    seed <- dat[dat$TTtreat != "" & dat$Measure != "Cover", c("turfID","subPlot", "year", "seedlings", "recorder")]  #get data.frame of seedlings      N1
    seed$subPlot <- as.integer(as.character(seed$subPlot))
    seed$turfID <- factor(seed$turfID)
    seedsum <- dbGetQuery(con, paste("select * from [number identified seedlings by subplot] where siteID='",dat$DestinationSite[1], "' and Year=2011", sep=""))     #sqlQuery database for number of seedlings per subplot N2
    seed <- seed[order(seed$turfID, seed$subPlot),]
  
    head(seed)
    head(seedsum)
    identical(seed[,1:2], seedsum[,1:2])#$turfID)
    identical(seed[,2], seedsum[,2])
  
    identical(seed[,1], seedsum[,1])
    
    seed <- seed[!paste(seed$turf, seed$subPlot) %in% setdiff(paste(seed$turf, seed$subPlot), paste(seedsum$turf, seedsum$subTurf)),]#   then remove any missing rows as they have no species
    
    seed$seedlings[is.na(seed$seedlings)] <- 0
  
    seed$seedlings2 <- seed$seedlings
    seed$seedlings2[seed$recorder == "W"]<-seed$seedlings[seed$recorder == "W"]-seedsum$SumOfseedlings[seed$recorder == "W"]#for VV /W subplots n seedlings N1 =  N1 - N2
  
    data.frame(seed$recorder, seed$seedlings, seedsum$SumOfseedlings, seed$seedlings2)
  
    #insert N1 into subTurfCommunity as unident seedling
  
    seed <- seed[seed$seedlings2 > 0,]
    seed <- data.frame(turfID = seed$turfID, year = seed$year, subTurf = seed$subPlot, species = "seed.unid", seedlings = seed$seedlings2, juvenile = 0,adult = 0,fertile = 0,vegetative = 0,dominant = 0, cf = 1)
    dbWriteTable(con, "subTurfCommunity", seed, row.names=FALSE, append = TRUE)
  }
  ######################### vigdis seedling problem fixed  #########################
  
  })                                                                                                      #uncomment to loop
}


# Codes for deleting tables:
wipe <- function(){
  dbGetQuery(con, "Delete FROM subTurfCommunity")                            
  dbGetQuery(con, "Delete FROM subTurfEnvironment")
  dbGetQuery(con, "Delete FROM turfCommunity")
  dbGetQuery(con, "Delete FROM turfEnvironment")
   #dbGetQuery(con, "Delete * FROM turfs")
  message("Database wiped. Hope you really wanted to do that!")
}

 
#replace mytable with a table you want to clean
#duplicate lines as necessary to clean all tables
#delete tables in the correct order or it won't work
#Then just run wipe() to clean the database