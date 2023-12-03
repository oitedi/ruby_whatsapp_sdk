module WhatsappSdk
  module Resource
    class Languages
      AVAILABLE_LANGUAGES = Set.new([
        "af", # Afrikaans
        "sq", # Albanian
        "ar", # Arabic
        "az", # Azerbaijani
        "bn", # Bengali
        "bg", # Bulgarian
        "ca", # Catalan
        "zh_CN", # Chinese (CHN)
        "zh_HK", # Chinese (HKG)
        "zh_TW", # Chinese (TAI)
        "hr", # Croatian
        "cs", # Czech
        "da", # Danish
        "nl", # Dutch
        "en", # English
        "en_GB", # English (UK)
        "en_US", # English (US)
        "et", # Estonian
        "fil", # Filipino
        "fi", # Finnish
        "fr", # French
        "ka", # Georgian
        "de", # German
        "el", # Greek
        "gu", # Gujarati
        "ha", # Hausa
        "he", # Hebrew
        "hi", # Hindi
        "hu", # Hungarian
        "id", # Indonesian
        "ga", # Irish
        "it", # Italian
        "ja", #Japanese
        "kn", #Kannada
        "kk", #Kazakh
        "rw_RW", #Kinyarwanda
        "ko", #Korean
        "ky_KG", #Kyrgyz (Kyrgyzstan)
        "lo", #Lao
        "lv", #Latvian
        "lt", #Lithuanian
        "mk", # Macedonian
        "ms", # Malay
        "ml", # Malayalam
        "mr", # Marathi
        "nb", # Norwegian
        "fa", # Persian
        "pl", # Polish
        "pt_BR", # Portuguese (BR)
        "pt_PT", # Portuguese (POR)
        "pa", # Punjabi
        "ro", # Romanian
        "ru", # Russian
        "sr", # Serbian
        "sk", # Slovak
        "sl", # Slovenian
        "es", # Spanish
        "es_AR", # Spanish (ARG)
        "es_ES", # Spanish (SPA)
        "es_MX", # Spanish (MEX)
        "sw", # Swahili
        "sv", # Swedish
        "ta", # Tamil
        "te", # Telugu
        "th", # Thai
        "tr", # Turkish
        "uk", # Ukrainian
        "ur", # Urdu
        "uz", # Uzbek
        "vi", # Vietnamese
        "zu", # Zulu
      ])

      def self.available?(language)
        AVAILABLE_LANGUAGES.include?(language)
      end
    end
  end
end
