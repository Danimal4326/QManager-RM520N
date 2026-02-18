"use client"

import * as React from "react"
import { ChevronRight, type LucideIcon } from "lucide-react"
import { usePathname } from "next/navigation"

import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"

import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuAction,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
} from "@/components/ui/sidebar"

export function NavCellular({
  cellular,
}: {
  cellular: {
    title: string
    url: string
    icon: LucideIcon
    isActive?: boolean
    items?: {
      title: string
      url: string
    }[]
  }[]
}) {
  const pathname = usePathname()
  const [openItems, setOpenItems] = React.useState<Record<string, boolean>>({})

  React.useEffect(() => {
    const states: Record<string, boolean> = {}
    cellular.forEach((item) => {
      const isActive = pathname === item.url
      const isChildActive = item.items?.some((subItem) => pathname === subItem.url) ?? false
      states[item.title] = isActive || isChildActive
    })
    setOpenItems(states)
  }, [pathname, cellular])

  return (
    <SidebarGroup>
      <SidebarGroupLabel>
        Cellular
      </SidebarGroupLabel>
      <SidebarMenu>
        {cellular.map((item) => {
          // Check if current path matches this item or any of its children
          const isActive = pathname === item.url
          const isChildActive = item.items?.some((subItem) => pathname === subItem.url) ?? false
          const isParentOrChildActive = isActive || isChildActive

          return (
          <Collapsible
            key={item.title}
            asChild
            open={openItems[item.title] ?? false}
            onOpenChange={(isOpen) => setOpenItems((prev) => ({ ...prev, [item.title]: isOpen }))}
          >
            <SidebarMenuItem>
              <SidebarMenuButton asChild tooltip={item.title} isActive={isParentOrChildActive}>
                <a href={item.url}>
                  <item.icon />
                  <span>{item.title}</span>
                </a>
              </SidebarMenuButton>
              {item.items?.length ? (
                <>
                  <CollapsibleTrigger asChild>
                    <SidebarMenuAction className="data-[state=open]:rotate-90">
                      <ChevronRight />
                      <span className="sr-only">Toggle</span>
                    </SidebarMenuAction>
                  </CollapsibleTrigger>
                  <CollapsibleContent>
                    <SidebarMenuSub>
                      {item.items?.map((subItem) => {
                        const isSubItemActive = pathname === subItem.url
                        return (
                        <SidebarMenuSubItem key={subItem.title}>
                          <SidebarMenuSubButton asChild isActive={isSubItemActive}>
                            <a href={subItem.url}>
                              <span>{subItem.title}</span>
                            </a>
                          </SidebarMenuSubButton>
                        </SidebarMenuSubItem>
                      )})}
                    </SidebarMenuSub>
                  </CollapsibleContent>
                </>
              ) : null}
            </SidebarMenuItem>
          </Collapsible>
        )})}
      </SidebarMenu>
    </SidebarGroup>
  )
}
