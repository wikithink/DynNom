utils::globalVariables(c("counter", "Prediction", "input.data", "old.d", "old.d2", "surv", "event", "n.risk", "part"))

DynNom.cph <- function(model, data,
                       clevel = 0.95, covariate = c("slider", "numeric"),
                       ptype = c("st", "1-st")) {
  
  data <- data.frame(data)
  model <- update(model,x=T, y=T, surv=T)
  
  if(dim(model$y)[2]==3)
    stop("Error in model syntax: models with start-stop time is not supported")       ##### error!
  
  
  if (length(dim(data)) > 2)
    stop("Error in data format: dataframe format required")
  
  if(length(class(model$y))==1){
    if (class(model$y)[1] == "logical")  stop("Error in model syntax: logical form for response not supported")} else{
      if (class(model$y)[2] == "logical")  stop("Error in model syntax: logical form for response not supported")
    }
  
  if (model$call[[2]][[3]]==1) {                               
    stop("Error in model syntax: the model is null")
  }
  
  vars=c()
  for(i in 1:length(model$Design$name)){
    if(model$Design$assume[i]!="interaction") vars[i] <- as.character(model$Design$name[i]) else vars[i]="inter"
  }
  vars <- subset(vars,vars!="inter")
  vars <- as.character(c(model$terms[[2]],vars))
  cvars <- NULL
  cvars[1] <- "survdata"
  for(i in 2:length(vars))  cvars[i]=model$Design$assume[i-1]
  
  
  n.strata <- length(attr(model$terms, "specials")$strat)
  dim.terms <- length(vars)
  
  ####################################################  
  #  if (!is.null(attr(model$terms, "specials")$tt)) {                                             
  #    stop("Error in model syntax: coxph models with a time dependent covariate is not supported")
  #  }
  ####################################################  
  
  covariate <- match.arg(covariate)
  ptype <- match.arg(ptype)
  input.data <- NULL
  old.d <- NULL
  
  n.strata <- length(attr(model$terms, "specials")$strat)       
  
  runApp(list(
    
    ui = bootstrapPage(fluidPage(
      titlePanel("Dynamic Nomogram"),
      sidebarLayout(sidebarPanel(uiOutput("manySliders.f"),
                                 uiOutput("manySliders.n"),
                                 checkboxInput("trans", "Alpha blending (transparency)", value = TRUE),
                                 actionButton("add", "Predict"),
                                 br(), br(),
                                 helpText("Press Quit to exit the application"),
                                 actionButton("quit", "Quit")
      ),
      mainPanel(tabsetPanel(id = "tabs",
                            tabPanel("Estimated S(t)", plotOutput("plot")),
                            tabPanel("Predicted Survival", plotOutput("plot2")),
                            tabPanel("Numerical Summary", verbatimTextOutput("data.pred")),
                            tabPanel("Model Summary", verbatimTextOutput("summary"))
      )
      )
      ))),
    
    server = function(input, output){
      
      observe({
        if (input$quit == 1)
          stopApp()
      })
      
      neededVar <- vars[-1]
      if (length(attr(model$terms, "term.labels")) == 1) {
        input.data <<- data.frame(data[1, neededVar])
        names(input.data)[1] <<- vars[-1]
      } else {
        input.data <<- data[1, neededVar]
      }
      input.data[1, ] <<- NA
      
      b <- 1
      i.factor <- NULL
      i.numeric <- NULL
      for (j in 2:length(vars)) {
        for (i in 1:length(data)) {
          if (vars[j] == names(data)[i]) {
            if (cvars[j] == "category" |
                cvars[j] == "scored"|
                cvars[j] == "factor"|
                cvars[j] == "strata"|
                cvars[j] == "ordered") {
              i.factor <- rbind(i.factor, c(vars[j], j, i, b))
              (break)()
            }
            if (cvars[j] == "rcspline"|
                cvars[j] == "asis"|
                cvars[j] == "lspline"|
                cvars[j] == "polynomial"|
                cvars[j] == "numeric" |
                cvars[j] == "integer"|
                cvars[j] == "double"|
                cvars[j] == "matrix") {
              i.numeric <- rbind(i.numeric, c(vars[j], j, i))
              b <- b + 1
              (break)()
            }
          }
        }
      }
      
      tt=vars[1]
      
      nnn=nchar(tt)
      char <- c()
      for(i in 1:(nnn-4)){
        cha <- substring(tt,i,i+4)
        if(cha == "Surv(") char[i] = 1 else char[i]=0
      }
      
      if(sum(char)==1){
        dd <- unlist(strsplit(substr(tt, 6, nchar(tt) - 1), "[,]"))
        tim <- dd[1]
      } else{
        tim <- colnames(model$y)[1]
      }
      
      sts <- colnames(model$y)[2]
      
      if (length(attr(model$terms, "term.labels")) == 1) {
        input.data <<- data.frame(cbind(stt = NA, ti = NA, cov = NA), NO=NA)
        names(input.data)[3] <<- neededVar
        names(input.data)[1:2] <<- c(paste(sts), paste(tim))
      } else{
        data1 <- data[, neededVar]
        input.data <<- cbind(stt = NA, ti = NA, data1[1, ], NO=NA)
        names(input.data)[1:2] <<- c(paste(sts), paste(tim))
        input.data[1, ] <<- NA
      }
      
      
      if (length(i.numeric) == 0) {
        i.numeric <- matrix(ncol = 3)
        i.numeric <- rbind(i.numeric, V1 = paste(tim))
        i.numeric <- rbind(i.numeric, V1 = paste(sts))
        i.numeric <- i.numeric[-1, ]
      } else{
        i.numeric <- rbind(i.numeric, V1 = paste(tim))
        i.numeric <- rbind(i.numeric, V1 = paste(sts))
      }
      
      nn <- nrow(i.numeric)
      if (is.null(nn)) {
        nn <- 0
      }
      nf <- nrow(i.factor)
      if (is.null(nf)) {
        nf <- 0
      }
      
      if (nf > 0) {
        output$manySliders.f <- renderUI({
          slide.bars <- list(lapply(1:nf, function(j) {
            selectInput(paste("factor", j, sep = ""),
                        vars[as.numeric(i.factor[j, 2])],
                        model$Design$parms[[i.factor[j,1]]], multiple = FALSE)
          }))
          do.call(tagList, slide.bars)
        })
      }
      
      
      if (nn > 1) {
        output$manySliders.n <- renderUI({
          if (covariate == "slider") {
            if (nn > 2){
              slide.bars <- list(lapply(1:(nn - 2), function(j) {
                sliderInput(paste("numeric", j, sep = ""), i.numeric[j, 1],
                            min = as.integer(min(na.omit(data[, as.numeric(i.numeric[j, 3])]))),
                            max = as.integer(max(na.omit(data[, as.numeric(i.numeric[j, 3])]))) + 1,
                            value = as.integer(mean(na.omit(data[, as.numeric(i.numeric[j, 3])]))))
              }), br(), checkboxInput("times", "Predicted Survival at this Follow Up:"),
              conditionalPanel(condition = "input.times == true",
                               sliderInput(paste("numeric", (nn - 1), sep = ""), i.numeric[(nn - 1), 1],
                                           min = as.integer(min(na.omit(model$y[,1]))),
                                           max = as.integer(max(na.omit(model$y[,1]))) + 1,
                                           value = as.integer(mean(na.omit(model$y[,1]))))
              ))
            }
            
            if (nn == 2){ 
              slide.bars <- list(br(), checkboxInput("times", "Predicted Survival at this Follow Up:"),
                                 conditionalPanel(condition = "input.times == true",
                                                  sliderInput(paste("numeric", (nn - 1), sep = ""), i.numeric[(nn - 1), 1],
                                                              min = as.integer(min(na.omit(model$y[,1]))),
                                                              max = as.integer(max(na.omit(model$y[,1]))) + 1,
                                                              value = as.integer(mean(na.omit(model$y[,1]))))
                                 ))
            }
            
          }
          
          if (covariate == "numeric") { 
            if (nn > 2){ 
              slide.bars <- list(lapply(1:(nn - 2), function(j) {
                numericInput(paste("numeric", j, sep = ""), i.numeric[j, 1],
                             value = as.integer(mean(na.omit(data[, as.numeric(i.numeric[j, 3])]))))
              }), br(), checkboxInput("times", "Predicted Survival at this Follow Up:"),
              conditionalPanel(condition = "input.times == true",
                               numericInput(paste("numeric", (nn - 1), sep = ""), i.numeric[(nn - 1), 1],
                                            value = as.integer(mean(na.omit(model$y[,1]))))))
            }
            if (nn == 2){
              slide.bars <- list(br(), checkboxInput("times", "Predicted Survival at this Follow Up:"),
                                 conditionalPanel(condition = "input.times == true",
                                                  numericInput(paste("numeric", (nn - 1), sep = ""), i.numeric[(nn - 1), 1],
                                                               value = as.integer(mean(na.omit(model$y[,1]))))))
            }
          }
          
          do.call(tagList, slide.bars)
          
        })
      }
      
      
      
      a <- 0
      new.d <- reactive({
        if (nf > 0) {
          input.f <- vector("list", nf)
          for (i in 1:nf) {
            input.f[[i]] <- local({
              input[[paste("factor", i, sep = "")]]
            })
            names(input.f)[i] <- i.factor[i, 1]
          }
        }
        if (nn > 1) {
          input.n <- vector("list", (nn - 1))
          for (i in 1:(nn - 1)) {
            input.n[[i]] <- local({
              input[[paste("numeric", i, sep = "")]]
            })
            names(input.n)[i] <- i.numeric[i, 1]
          }
        }
        if (nn == 0) {
          out <- data.frame(do.call("cbind", input.f))
          colnames(out)[dim(out)[2]] <- tim
        }
        if (nf == 0) {
          out <- data.frame(do.call("cbind", input.n))
          colnames(out)[dim(out)[2]] <- tim
        }
        if (nf > 0 & nn > 0) {
          out <- data.frame(do.call("cbind", input.f), do.call("cbind", input.n))
          colnames(out)[dim(out)[2]] <- tim
        }
        if (a == 0) {
          wher <- match(names(out), names(input.data)[-1])
          out2 <- cbind(out[wher], NO=input$add)
          input.data <<- rbind(input.data[-1], out2)
        }
        if (a > 0) {
          wher <- match(names(out), names(input.data))
          out2 <- cbind(out[wher], NO=input$add)
          input.data <<- rbind(input.data, out2)
        }
        a <<- a + 1
        out
      })
      
      p1 <- NULL
      old.d <- NULL
      data2 <- reactive({
        if (input$add == 0)
          return(NULL)
        if (input$add > 0) {
          OUT <- isolate({
            if (isTRUE(compare(old.d, new.d())) == FALSE) {
              new.d <- cbind(stat = 1, new.d())
              names(new.d)[1] <- paste(sts)
              
                #       if (is.error(try(survfit(model,new.d)))==T){
                #        stop("Error in data structure: There is not enough data in the current strata level")
                #       }
                         
              
              if (is.error(try(survest(model, newdata=new.d(),times=new.d()[,paste(tim)],conf.int=clevel)))==T) {
                d.p <- data.frame(Prediction = NA, Lower.bound = NA,
                                  Upper.bound = NA)
              } else{
                pred <- survest(model, newdata=new.d,times=new.d[,paste(tim)],conf.int=clevel)
                
                upb <- round(pred$upper,digits = 4)   
                
                if (upb > 1) {
                  upb <- 1
                }
                lwb <- round(pred$lower,digits = 4)
                
                if (ptype == "st") {
                  d.p <- data.frame(Prediction = round(pred$surv,digits=4), Lower.bound = lwb,
                                    Upper.bound = upb)
                }
                if (ptype == "1-st") {
                  d.p <- data.frame(Prediction = 1 - round(pred$surv,digits=4), Lower.bound = 1 - upb,  
                                    Upper.bound = 1 - lwb)
                  
                }
              } 
              
              old.d <<- new.d()
              data.p <- cbind(d.p, counter = 1, NO=input$add)
              p1 <<- rbind(p1, data.p)
              
              p1$count <- seq(1, dim(p1)[1])
              p1
              
            }
            
            else {
              p1$count <- seq(1, dim(p1)[1])
              OUT <- p1
            }
          })
        }
        OUT
      })
      
     
      
      s.fr <- NULL
      old.d2 <- NULL
      b <- 1
      St <- TRUE
      
      if (n.strata > 0) {
        sub.fit1 <- reactive({
          
          if (is.error(try(survfit(model,new.d())))==T){
            stop("Error in data structure: There is not enough data in the current strata level")
          }
          
          fit1 <- survfit(model, newdata = new.d())
          
          aa <- 0
          for(i in 1:length(model$Design$name)){
            if(model$Design$assume[i]=="strata"){
              nam0 <- paste(model$Design$name[i],"=",new.d()[,paste(model$Design$name[i])], sep = "")
              if (aa == 0) {
                nam <- paste(nam0)
              }
              if (aa > 0) {
                nam <- paste(nam, ".", nam0, sep = "")
              }
              aa <- aa + 1
            } else{
              i <- i+1
            }
          }
          sub.fit1 <- subset(as.data.frame(summary(fit1)[2:8]), strata == nam)
          return(sub.fit1)
        })
      }
      
      dat.p <- reactive({
        if (isTRUE(compare(old.d2, new.d())) == FALSE) {
          s.frame <- isolate({
            if (is.error(try(survfit(model,new.d())))==T){
              stop("Error in data structure: There is not enough data in the current strata level")
            }
            fit1 <- survfit(model, newdata = new.d())
            if (n.strata == 0) {
              sff <- as.data.frame(summary(fit1)[2:8])
              sff <- cbind(sff, event=1-sff[[5]], part = b)
              if (sff$time[1] != 0){
                sff2 <- sff[1, ]
                sff2[1, ] <- NA
                sff2$time[1] <- 0
                sff2$n.risk[1] <- sum(model$n)
                sff2$surv[1] <- 1
                sff2$event[1] <- 0
                sff2$part[1] <- sff$part[1]
                s.f <- rbind(sff2, sff)
              } else {
                s.f <- sff
              }
            }
            if (n.strata > 0) {
              if (is.error(try(survfit(model,new.d())))==T){
                stop("Error in data structure: There is not enough data in the current strata level")
              }
              sff <- cbind(sub.fit1(), part = b)
              sff <- cbind(sff, event=1-sff[[6]])
              if (sff$time[1] != 0) {
                sff2 <- sff[1, ]
                sff2[1, ] <- NA
                sff2$time[1] <- 0
                sff2$n.risk[1] <- sff[1,2]
                sff2$surv[1] <- 1
                sff2$event[1] <- 0
                sff2$part[1] <- sff$part[1]
                s.f <- rbind(sff2, sff)
              } else {
                s.f <- sff
              }
              s.f$n.risk <- s.f$n.risk/s.f$n.risk[1]
            }
            if (dim(s.f)[1] < 3) {
              St <<- FALSE
              stop("Error in data structure: There is not enough data in the current strata level")
            }
            s.fr <<- rbind(s.fr, s.f)
            old.d2 <<- new.d()
            b <<- b + 1
            s.fr
          })
        } else {
          s.frame <- isolate({
            s.fr
          })
        }
      })
      
      output$plot <- renderPlot({
        if (St == TRUE) {
          if (input$add == 0)
            return(NULL)
          if (is.error(try(survfit(model,new.d())))==T)
            return(NULL)
          
          if (input$add > 0) {
            if (input$trans == TRUE) {
              if (ptype == "st") {
                
                pl <- isolate({
                  p2 <- ggplot(data = dat.p())
                  p2 <- p2 + geom_step(aes(x = time, y = surv, alpha = n.risk, color = as.factor(part), group = part))
                  p2 <- p2 + ylim(0, 1) + xlim(0, max(dat.p()$time) * 1.05)
                  p2 <- p2 + labs(title = "Estimated Survival Probability", x = "Follow Up Time", y = "S(t)") + theme_bw()
                  p2 <- p2 + theme(text = element_text(face = "bold", size = 14), legend.position = "none")
                })
              }
              if (ptype == "1-st") {
                pl <- isolate({
                  p2 <- ggplot(data = dat.p())
                  p2 <- p2 + geom_step(aes(x = time, y = event, alpha = n.risk, color = as.factor(part), group = part))
                  p2 <- p2 + ylim(0, 1) + xlim(0, max(dat.p()$time) * 1.05)
                  p2 <- p2 + labs(title = "Estimated Probability", x = "Follow Up Time", y = "F(t)")
                  p2 <- p2 + theme_bw() + theme(text = element_text(face = "bold", size = 14), legend.position = "none")
                })
              }
            }
            if (input$trans == FALSE) {
              if (ptype == "st") {
                pl <- isolate({
                  p2 <- ggplot(data = dat.p())
                  p2 <- p2 + geom_step(aes(x = time, y = surv, color = as.factor(part), group = part))
                  p2 <- p2 + ylim(0, 1) + xlim(0, max(dat.p()$time) * 1.05)
                  p2 <- p2 + labs(title = "Estimated Survival Probability", x = "Follow Up Time", y = "S(t)") + theme_bw()
                  p2 <- p2 + theme(text = element_text(face = "bold", size = 14), legend.position = "none")
                })
              }
              if (ptype == "1-st") {
                pl <- isolate({
                  p2 <- ggplot(data = dat.p())
                  p2 <- p2 + geom_step(aes(x = time, y = event, color = as.factor(part), group = part))
                  p2 <- p2 + ylim(0, 1) + xlim(0, max(dat.p()$time) * 1.05)
                  p2 <- p2 + labs(title = "Estimated Probability", x = "Follow Up Time", y = "F(t)")
                  p2 <- p2 + theme_bw() + theme(text = element_text(face = "bold", size = 14), legend.position = "none")
                })
              }
            }
          }
          data2()
          print(pl)
        }
        if (St == FALSE) {
          print("Restart the application")
        }
      })
      
      output$plot2 <- renderPlot({
        if (input$add == 0)
          return(NULL)
        
        isolate({
          if (is.null(new.d()))   return(NULL)
          if (dim(na.omit(data2()))[1]==0 ) return(NULL)  
          lim <- c(0, 1)
          yli <- c(0 - 0.5, 10 + 0.5)
          if (dim(input.data)[1] > 11)
            yli <- c(dim(input.data)[1] - 11.5, dim(input.data)[1] - 0.5)
          p <- ggplot(data = data2()[!is.na(data2()$Prediction),], aes(x = Prediction, y = 0:(sum(counter) - 1)))
          p <- p + geom_point(size = 4, colour = data2()$count[!is.na(data2()$Prediction)], shape = 15)  # count
          p <- p + ylim(yli[1], yli[2]) + coord_cartesian(xlim = lim)
          p <- p + geom_errorbarh(xmax = data2()$Upper.bound[!is.na(data2()$Prediction)], xmin = data2()$Lower.bound[!is.na(data2()$Prediction)],
                                  size = 1.45, height = 0.4, colour = data2()$count[!is.na(data2()$Prediction)])         # seq(1, dim(Prediction)[1])
          if (ptype == "st") {
            p <- p + labs(title = paste(clevel * 100, "% ", "Confidence Interval for Survival Probability", sep = ""),
                          x = "Survival Probability", y = NULL)
          }
          if (ptype == "1-st") {
            p <- p + labs(title = paste(clevel * 100, "% ", "Confidence Interval for F(t)", sep = ""),
                          x = "Probability", y = NULL)
          }
          p <- p + theme_bw() + theme(axis.text.y = element_blank(), text = element_text(face = "bold", size = 14))
          print(p)
        })
        data2()
      })
      
      output$data.pred <- renderPrint({
        if (input$add > 0) {
          isolate({
            if (nrow(data2() > 0)) {
              
              di <- ncol(input.data)
              data.p <- merge(input.data[-1, ], data2()[1:5], by="NO")
              data.p <- data.p[, !(colnames(data.p) %in% c("NO", "counter"))]
              data.p$Prediction[is.na(data.p$Prediction)] <- "Not"
              data.p$Lower.bound[is.na(data.p$Lower.bound)] <- "IN"
              data.p$Upper.bound[is.na(data.p$Upper.bound)] <- "RANGE"
              stargazer(data.p, summary = FALSE, type = "text")
            }
          })
          
        }
      })
      
      output$summary <- renderPrint({
        print(model)
      })
    }
  )
  )
}
