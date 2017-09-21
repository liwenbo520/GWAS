##############################################################################################################################################
###   AMM   -- R script for GWAS corecting for population structure (similar to EMMAX and P3D)
###
#######
#
##
## 
##		
#


##REQUIRED DATA & FORMAT

#requires functions from the original emma function (Kang et al. 2008, Genetics) 
#source('emma.r')
#PHENOTYPE - Y: a n by m matrix, where n=number of individuals and the rownames(Y) contains the individual names

#GENOTYPE - X: a n by m matrix, where n=number of individuals, m=number of SNPs, with rownames(X)=individual names, and colnames(X)=SNP names
#KINSHIP - K: a n by n matrix, with rownames(K)=colnames(K)=individual names, you can calculate K as IBS matrix using the emma package K<-emma.kinship(t(X)) 
#each of these data being sorted in the same way, according to the individual name
#
#
#SNP INFORMATION - SNP_INFO: a data frame having at least 3 columns:
# - 1 named 'SNP', with SNP names (same as colnames(X)),
# - 1 named 'Chr', with the chromosome number to which belong each SNP
# - 1 named 'Pos', with the position of the SNP onto the chromosome it belongs to.

#Y <- my_dorm
#K <- load('K_2029.rda')
#X <- load('X_2029_1.rda')
#m = 2 
#calculate.effect.size = TRUE
#include.lm = FALSE
#use.SNP_INFO = FALSE
#report = TRUE 


amm_gwas<-function(Y,X,K,p=0.001,m=2,run=TRUE,calculate.effect.size=TRUE,include.lm=FALSE,use.SNP_INFO=FALSE,update.top_snps=FALSE,report=TRUE,mc=TRUE, mc.cores = cores){
    if(mc==TRUE){
        registerDoMC(cores)
    }
    stopifnot(is.numeric(Y[,1]))
    Y_<-Y[order(Y[,1]),]
    Y<-as.matrix(Y_[,m])
    rownames(Y)<-Y_[,1]
    Y<-na.omit(Y)
    XX<-X[rownames(X) %in% rownames(Y),]
    if (report==TRUE) {
        cat ('GWAS performed on',length(which(rownames(Y)%in%rownames(X))),'ecotypes, ',nrow(Y)-length(which(rownames(Y)%in%rownames(X))),'values excluded','\n')
    }
    
    if (use.SNP_INFO==FALSE){ 
        options(stringsAsFactors = FALSE)
        if(report==TRUE) {
            cat('SNP_INFO file created','\n')}
        SNP_INFO<-data.frame(cbind(colnames(X),matrix(nrow=ncol(X),ncol=2,data=unlist(strsplit(colnames(X),split='- ')),byrow=T)))
        colnames(SNP_INFO)<-c('SNP','Chr','Pos')
        SNP_INFO[,2]<-as.numeric(SNP_INFO[,2])
        SNP_INFO[,3]<-as.numeric(SNP_INFO[,3])
    } else {if (report==TRUE) {cat('User definied SNP_INFO file is used','\n')}}
    

    Y1 <- as.matrix(Y[rownames(Y) %in% rownames(XX),])
    colnames(Y1) <- colnames(Y)
    rownames(Y1)<-rownames(Y)[rownames(Y)%in%rownames(XX)]
    ecot_id<-as.integer(rownames(Y1))

    K1<- K[rownames(K) %in% ecot_id,]
    K2<- K1[,colnames(K1) %in% ecot_id]
    K_ok <- as.matrix(K2)

    a <-rownames(K_ok)

    n <- length(a)
    K_stand <-(n-1)/sum((diag(n)-matrix(1,n,n)/n)*K_ok)*K_ok

    Y<-Y1[which(rownames(Y1)%in%a),]
    X_<-XX[which(rownames(XX)%in%a),]

    rm(X,XX)
    gc()


    #AC_1 <- data.frame(colnames(X_),apply(X_,2,sum)) ##colSums naturally works fast than apply(X_,2,sum)

    AC_1 <- data.frame(colnames(X_),colSums(X_))
    colnames(AC_1) <-c('SNP','AC_1')
    
    MAF_1 <-data.frame(AC_1,AC_0=nrow(X_)-AC_1$AC_1)
    MAF_2 <-data.frame(MAF_1,MAC=apply(MAF_1[,2:3],1,min))
    MAF_3 <-data.frame(MAF_2,MAF=(MAF_2$MAC/nrow(X_)))
    MAF_ok <-merge(SNP_INFO,MAF_3,by='SNP')

    rm(AC_1,MAF_1,MAF_2,MAF_3)

    #Filter MAF
    
    MAF<-subset(MAF_ok,MAF<p)[,1]

    X_ok<-X_[,!colnames(X_) %in% MAF]

    rm(MAF,X_)

    #REML
    Xo<-rep(1,nrow(X_ok))
    ex<-as.matrix(Xo)

    null<-emma.REMLE(Y,ex,K_stand)

    herit<-null$vg/(null$vg+null$ve)

    if (report==TRUE) {
        cat('pseudo-heritability estimate is ',herit,'\n')
    }

    if (run==FALSE) {
        cat('no GWAS performed','\n')
    } else {
        M <-solve(chol(null$vg*K_stand+null$ve*diag(dim(K_stand)[1])))
        Y_t<-crossprod(M,Y)
        int_t<-crossprod(M,(rep(1,length(Y))))
        

        if (calculate.effect.size==TRUE) {
            if(mc==FALSE){
                models1<-apply(X_ok,2,function(x){summary(lm(Y_t~0+int_t+crossprod(M,x)))$coeff[2,]}) 
                
            }else if(mc == TRUE){
                models1 <- foreach(x = 1:dim(X_ok)[2],.combine='rbind') %dopar%
                summary(lm(Y_t~0+int_t+crossprod(M,X_ok[,x])))$coeff[2,]
            
            rownames(models1) <- colnames(X_ok)
                models1 <- t(models1)
            }
        
        out_models <- data.frame(SNP=colnames(models1),Pval=models1[4,],beta=models1[1,])
        }else{
            
        RSS_env<-rep(sum(lsfit(int_t,Y_t,intercept = FALSE)$residuals^2),ncol(X_ok))
            
            if(mc==FALSE){
            
                R1_full<-apply(X_ok,2,function(x){sum(lsfit(cbind(int_t,crossprod(M,x)),Y_t,intercept = FALSE)$residuals^2)})
            } else if(mc == TRUE){
                R1_list <- mclapply(1:dim(X_ok)[2],function(x){sum(lsfit(cbind(int_t,crossprod(M,X_ok[,x])),Y_t,intercept = FALSE)$residuals^2,mc.cores=cores,mc.preschedule = T)})
                R1_full <- do.call('c',R1_list)
                names(R1_full) <- colnames(X_ok)
            }
            m <- nrow(Y1)
            F_1 <- ((RSS_env-R1_full)/1)/(R1_full/(m-3))
            pval_Y1 <- pf(F_1,1,(m-3),lower.tail=FALSE)
            
            snp<-colnames(X_ok)
            out_models <- data.frame(SNP=snp,Pval=pval_Y1,variance_explained=1-R1_full/RSS_env)
            }
        
        output<-merge(MAF_ok,out_models,by='SNP')
        
        if (include.lm==TRUE) {
            RSS_env_<-rep(sum(lsfit(rep(1,length(Y)),Y,intercept = FALSE)$residuals^2),ncol(X_ok))
            R1_full_<-apply(X_ok,2,function(x){sum(lsfit(x,Y,intercept = T)$residuals^2)})
            m<-nrow(Y1)
            
            F_1_<-((RSS_env_-R1_full_)/1)/(R1_full_/(m-3))
            pval_Y1_lm<-pf(F_1_,1,(m-3),lower.tail=FALSE)
            
            snp<-colnames(X_ok)
            out_models_lm<-data.frame(SNP=snp,Pval_lm=pval_Y1_lm)
            output<-merge(output,out_models_lm,by='SNP')
            
        }
        
    ## update tp SNPs with correct model 
        if (update.top_snps==FALSE) {
            return(output)
        } else {
            
            oi<-output[order(output[,8]),][1:update.top_snps,1]
            
            
            xs=t(X_ok[,colnames(X_ok)%in%oi])
            
            
            auto<-emma.ML.LRT (Y, xs, K_ok)
            
            up<-data.frame(SNP=rownames(xs),update=auto$ps[,1])
            
            for ( i in 1: update.top_snps) {
                output[which(output[,1]==up[i,1]),8]<-up[i,2]
        }
            
            return(output)
        }
    }
}








