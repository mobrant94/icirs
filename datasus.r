pacman::p_load(
  "dplyr",
  "ggplot2",
  "ggthemes",
  "lubridate",
  "readxl",
  "tidyverse",
  "janitor"
)

setwd("C:/Users/MARCOS.ANTUNES/Downloads")

df = read_excel("painel_final_.xlsx")


df <- df %>%
  clean_names() %>%
  mutate(
    tempo_ate_trat = as.numeric(difftime(dt_trat, dt_diag, units = "days"))
  )

df <- df %>%
  mutate(
    faixa_etaria = if_else(idade < 12, "<12", "≥12")
  )

df <- df %>%
  mutate(
    regiao = case_when(
      uf_resid %in% c("AC", "AP", "AM", "PA", "RO", "RR", "TO") ~ "Norte",
      uf_resid %in% c("AL", "BA", "CE", "MA", "PB", "PE", "PI", "RN", "SE") ~ "Nordeste",
      uf_resid %in% c("DF", "GO", "MT", "MS") ~ "Centro-Oeste",
      uf_resid %in% c("ES", "MG", "RJ", "SP") ~ "Sudeste",
      uf_resid %in% c("PR", "RS", "SC") ~ "Sul",
      TRUE ~ NA_character_
    )
  )

df <- df %>%
  mutate(
    tempo_cat = case_when(
      tempo_ate_trat < 1 ~ "<1 dia",
      tempo_ate_trat >= 2 & tempo_ate_trat < 7 ~ "2-6 dias",
      tempo_ate_trat >= 7 & tempo_ate_trat <= 15 ~ "7-15 dias",
      tempo_ate_trat > 15 & tempo_ate_trat <= 30 ~ "15-30 dias",
      tempo_ate_trat > 30 & tempo_ate_trat <= 60 ~ "1-2 meses",
      tempo_ate_trat > 60 & tempo_ate_trat <= 90 ~ "2-3 meses",
      tempo_ate_trat > 90 ~ "≥3 meses",
      TRUE ~ NA_character_
    ),
    tempo_cat = factor(
      tempo_cat,
      levels = c("<1 dia","<7 dias", "7-15 dias", "15-30 dias", "1-2 meses", "2-3 meses", "≥3 meses"),
      ordered = TRUE
    )
  )


###

library(dplyr)

tabela_resumo <- df %>%
  group_by(faixa_etaria) %>%
  summarise(
    n = sum(!is.na(tempo_ate_trat)),
    media = mean(tempo_ate_trat, na.rm = TRUE),
    dp = sd(tempo_ate_trat, na.rm = TRUE),
    mediana = median(tempo_ate_trat, na.rm = TRUE),
    p25 = quantile(tempo_ate_trat, 0.25, na.rm = TRUE),
    p75 = quantile(tempo_ate_trat, 0.75, na.rm = TRUE)
  ) %>%
  mutate(
    media_dp = sprintf("%.1f ± %.1f", media, dp),
    mediana_iqr = sprintf("%.1f (%.1f–%.1f)", mediana, p25, p75)
  ) %>%
  select(faixa_etaria, n, media_dp, mediana_iqr)


#########

library(flextable)
library(officer)

flextab <- tabela_resumo %>%
  flextable() %>%
  set_header_labels(
    faixa_etaria = "Faixa etária",
    n = "n",
    media_dp = "Tempo médio ± DP (dias)",
    mediana_iqr = "Mediana (P25–P75) (dias)"
  ) %>%
  autofit()

doc <- read_docx() %>%
  body_add_par("Tabela: Tempo entre diagnóstico e tratamento por faixa etária", style = "heading 1") %>%
  body_add_flextable(flextab)

print(doc, target = "tempo_diagnostico_tratamento.docx")



#############


library(ggplot2)
library(dplyr)
library(scales)
library(viridis) # Instale se não tiver: install.packages("viridis")

# Calcule os percentuais
df_plot <- df %>% filter(!(tempo_ate_trat<0)) %>% 
  filter(!is.na(tempo_cat), !is.na(faixa_etaria)) %>%
  group_by(tempo_cat, faixa_etaria) %>%
  summarise(n = n(), .groups = "drop") %>%
  mutate(percent = n / sum(n) * 100)

# Gráfico
ggplot(df_plot, aes(x = tempo_cat, y = n, fill = faixa_etaria)) +
  geom_bar(stat = "identity", 
           position = position_dodge2(width = 0.9, 
                                      preserve = "single", 
                                      padding = 0), 
           width = 0.85, color = "black") +
  geom_text(
    aes(label = paste0(round(percent, 1), "%")),
    position = position_dodge2(width = 0.9, preserve = "single", padding = 0),
    vjust = -0.2, # Coloca o texto acima da barra
    color = "black",
    size = 4,
    fontface = "bold"
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.05)))+
  scale_fill_brewer(palette = "Dark2", name = "Faixa etária") +
  labs(
    title = "Distribuição da faixa etária por tempo até o tratamento",
    x = "Tempo até início do tratamento",
    y = "Frequência absoluta"
  ) +
  theme_classic(base_size = 14) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1),
    legend.position = "right"
  )


dados_modelo = df %>% filter(!(tempo_ate_trat<1))

dados_modelo <- dados_modelo %>%
  filter(!is.na(tempo_ate_trat), !is.na(faixa_etaria), !is.na(regiao), !is.na(sgruphab))

# Ajustar GLM com Gamma e interação faixa_etaria * regiao
modelo <- glm(
  tempo_ate_trat ~ faixa_etaria + regiao + estadiam + sgruphab,
  data = dados_modelo,
  family = Gamma(link = "log")
)

# Estimar médias marginais ajustadas por faixa_etaria dentro de cada região
emm <- emmeans(modelo, ~ faixa_etaria, type = "response")
emm_df <- as.data.frame(emm)

# Plotar médias marginais ajustadas por faixa_etaria e região
ggplot(emm_df, aes(x = faixa_etaria, y = response, color = faixa_etaria, group = faixa_etaria)) +
  geom_point(position = position_dodge(width = 0.5), size = 3) +
  geom_errorbar(aes(ymin = lower.CL, ymax = upper.CL),
                width = 0.2,
                position = position_dodge(width = 0.5)) +
  labs(
    title = "Tempo médio ajustado entre diagnóstico e tratamento",
    subtitle = "Por e faixa etária (ajustado por região e habilitação)",
    x = "Faixa etária",
    y = "Tempo médio ajustado (dias)",
    color = "Faixa etária"
  ) +
  theme_classic() +
  theme(
    legend.position = "top",
    plot.title = element_text(face = "bold"),
  )

# Estimar médias marginais ajustadas por faixa_etaria dentro de cada região
emm1 <- emmeans(modelo, ~ faixa_etaria|regiao, type = "response")
emm_df1 <- as.data.frame(emm1)

# Plotar médias marginais ajustadas por faixa_etaria e região
ggplot(emm_df1, aes(x = regiao, y = response, color = faixa_etaria, group = faixa_etaria)) +
  geom_point(position = position_dodge(width = 0.5), size = 3) +
  geom_errorbar(aes(ymin = lower.CL, ymax = upper.CL),
                width = 0.2,
                position = position_dodge(width = 0.5)) +
  labs(
    title = "Tempo médio ajustado entre diagnóstico e tratamento",
    subtitle = "Por e faixa etária (ajustado por região e habilitação)",
    x = "Faixa etária",
    y = "Tempo médio ajustado (dias)",
    color = "Faixa etária"
  ) +
  theme_classic() +
  theme(
    legend.position = "top",
    plot.title = element_text(face = "bold"),
  )

